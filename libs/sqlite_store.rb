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

      db.create_table(:pages) do
        primary_key :id, type: Bignum
        String :page_id, unique: true
        Text :title
        Text :content
        String :creator
      end

      db.create_table(:users) do
        primary_key :id, type: Bignum
        String :username, unique: true
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

      FlatFileStore.new.list.each { |id|
        data = FlatFileStore.new.load(id)
        title = data[:title]
        content = data[:content]

        db[:pages].insert(page_id: id, title: title, content: content)
      }

      db.run 'PRAGMA journal_mode=WAL'

      self.close
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

if store.version == -1
  store.migrate
end
