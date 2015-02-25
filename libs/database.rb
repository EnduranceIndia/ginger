require 'rubygems'
require 'sequel'
require 'pg'
require 'mysql'

require 'time'

class DatabaseConnection
	def initialize(adapter, datasource)
		if datasource['type'] == 'sqlite'
			@connection = Sequel.sqlite(CONF['base_files_directory'] + '/' + datasource['filename'])
		else
			@connection = Sequel.connect(:adapter => adapter, :host => datasource['hostname'], :username => datasource['username'], :password => datasource['password'], :database => datasource['database'])
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
					value = value.gmtime.strftime("%Y-%m-%d %H:%M:%S")
				end

				value
			}
		}

		cols = cols.collect {|name| name.to_s }

		[cols, table]
	end

	def queryables
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

		return tables
	end

	def fields_for(queryable)
		@connection.schema(queryable).collect {|column|
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

def connect(datasource, database=nil)
	if database
		datasource['database'] = database
	end

	DatabaseConnection.new(datasource['type'], datasource)
end
