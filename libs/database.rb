require 'rubygems'
require 'sequel'
require 'pg'
require 'mysql'

require 'time'

class DatabaseConnection
	def initialize(adapter, data_source)
		if data_source[:type] == 'sqlite'
			@connection = Sequel.sqlite(CONF[:base_files_directory] + '/' + data_source[:filename])
		else
			@connection = Sequel.connect(:adapter => adapter, :host => data_source[:hostname], :username => data_source[:username], :password => data_source[:password], :database => data_source[:database])
		end
	end

	def escape(value)
		@connection.literal(value)
	end

	def query_table(query, *params)
		result = params.length > 0 ? @connection[query, params] : @connection[query]

		cols = result.columns
		table = result.collect {|row|
			cols.collect {|name|
				value = row[name]

				value = value.to_time if value.is_a?(DateTime)
				if value.is_a?(Time)
					value = value.gmtime.strftime('%Y-%m-%d %H:%M:%S')
				end

				value
			}
		}

		cols = cols.collect {|name| name.to_s }

		[cols, table]
	end

	def query_tables
		tables = @connection.tables.collect {|table| table.to_s }.sort
		views = @connection.views.collect {|view| view.to_s }

		views.each {|view|
			m = /_(\w+)/.match(view)
			if m && m.length > 1
				table = /_(\w+)/.match(view)[1]
			else
				table = nil
			end

			index = table ? tables.index(table) : nil
			tables[index] = view if index
		}

		tables
	end

	def fields_for(query_table)
		@connection.schema(query_table).collect {|column|
			name, type_info = column

			{
				name: name,
				db_type: type_info[:db_type],
				primary_key: type_info[:primary_key],
				allow_null: type_info[:allow_null]
			}
		}
	end
end

def connect(data_source, database=nil)
	if database
		data_source[:database] = database
	end

	DatabaseConnection.new(data_source[:type], data_source)
end
