class SQLiteStore
  attr_reader :version

  def initialize
    @version = get_version
  end

  def db_file_path
    get_base_path('data.sqlite')
  end

  def db_exists
    File.exist?(db_file_path)
  end

  def db
    @db = Sequel.sqlite(db_file_path) if @db.equal?(nil)
    @db
  end

  def get_version
    if db.table_exists?(:version)
      version = db[:version].get(:version).to_i
    else
      version = -1
    end

    self.close
    version
  end

  def get_base_path(file_path)
    get_conf[:base_files_directory] + "/#{file_path}"
  end

  def update_database_version(version)
    db[:version].update(:version => version)
    self.close
  end

  def migrate
    if @version == -1
      db.create_table(:version) do
        Bignum :version
      end

      db[:version].insert(0)
      @version = 0

      db.create_table(:pages) do
        primary_key :id, type: Bignum
        String :page_id, unique: true
        Text :title
        Text :content
      end

      FlatFileStore.new.list.each { |id|
        data = FlatFileStore.new.load(id)
        title = data[:title]
        content = data[:content]

        db[:pages].insert(page_id: id, title: title, content: content)
      }

      db.run 'PRAGMA journal_mode=WAL'

      self.close
    end

    if @version == 0
      begin
        # Patch existing tables
        db.alter_table(:pages) do
          add_column :creator, String, :default=>'Ginger'
        end

        # Create new tables
        db.create_table(:users) do
          primary_key :id, type: Bignum
          String :username, unique: true
        end

        db.create_table(:groups) do
          primary_key :id, type: Bignum
          String :group_name, unique: true
          String :creator
        end

        db.create_table(:group_users) do
          String :group_name
          String :username
          primary_key :group_name, :username
        end

        db.create_table(:data_sources) do
          primary_key :id, type: Bignum
          String :data_source_name, unique: true
          String :creator
        end

        db.create_table(:data_source_attributes) do
          String :data_source_name
          String :attribute_name
          String :attribute_value
          primary_key :data_source_name, :attribute_name
        end

        db.create_table(:data_source_permissions) do
          String :data_source_name
          String :entity
          String :entity_name
          String :permission
        end

        db.create_table(:page_permissions) do
          String :page_id
          String :entity
          String :entity_name
          String :permission
        end

        # Migrate data
        conf = get_conf
        if conf.has_key?('datasources')
          data_sources_hash = conf['datasources']

          data_sources_hash.each do |data_source_name, data_source_attributes|
            db[:data_sources].insert(data_source_name: data_source_name, creator: 'Ginger')
            db[:data_source_permissions].insert(data_source_name: data_source_name,
                                                entity: 'all',
                                                entity_name: 'all',
                                                permission: 'read')
            data_source_attributes.each do |attribute_name, attribute_value|
              db[:data_source_attributes].insert(data_source_name: data_source_name,
                                                 attribute_name: attribute_name,
                                                 attribute_value: attribute_value)
            end
          end
        end

        pages = db[:pages].collect
        pages.each do |page|
          db[:page_permissions].insert(page_id: page[:page_id],
                                       entity: 'all',
                                       entity_name: 'all',
                                       permission: 'read')
        end

        update_database_version(1)
        @version = 1

        self.close
      rescue
        $stderr.write("Database already patched, skipping\n")
      end
    end
  end

  def close
    if @db
      @db.disconnect
      @db = nil
    end
  end
end

store = SQLiteStore.new
store.migrate
