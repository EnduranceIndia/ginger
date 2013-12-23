require 'rubygems'
require 'sequel'
require 'pg'
require 'mysql'

class DatabaseConnection
	def initialize(adapter, datasource)
		@connection = Sequel.connect(:adapter => adapter, :host => datasource['hostname'], :username => datasource['username'], :password => datasource['password'], :database => datasource['database'])
	end

	def escape(value)
		@connection.literal(value)
	end

	def query_table(query, *params)
		result = params.length > 0 ? @connection[query, params] : @connection[query]

		cols = result.columns
		table = result.collect {|row|
			cols.collect {|name| row[name] }
		}

		cols = cols.collect {|name| name.to_s }

		[cols, table]
	end
end

def connect(datasource, database=nil)
	if database
		datasource['database'] = database
	end

	DatabaseConnection.new(datasource['type'], datasource)
end
