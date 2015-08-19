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
    return @db if @db != nil
    Sequel.sqlite(db_file_path)
  end

  def get_version
    return db[:version].get(:version).to_i if db.table_exists?(:version)
    -1
  end

  def get_base_path(file_path)
    get_conf[:base_files_directory] + "/#{file_path}"
  end

  def update_database_version(version)
    db[:version].update(:version => version)
  end

  def migrate
    if @version == -1
      db.create_table(:version) do
        Bignum :version
      end

      db.create_table(:pages) do
        primary_key :id, type: Bignum
        String :page_id, unique: true
        Text :title
        Text :content
      end

      db.create_table(:users) do
        primary_key :id, type: Bignum
        String :username, unique: true
      end

      db[:version].insert(0)

      FlatFileStore.new.list.each { |id|
        data = FlatFileStore.new.load(id)
        title = data[:title]
        content = data[:content]

        db[:pages].insert(page_id: id, title: title, content: content)
      }

      db.run 'PRAGMA journal_mode=WAL'
    end
  end

  def close
    if @db
      @db.disconnect
      @db = nil
    end
  end
end