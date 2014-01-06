require './libs/page_utils.rb'

def format(connection, value, type)
	return escape(connection, value) if type == 'string'
	return value
end

def escape(connection, value)
	return "#{strip_quotes(connection.escape(value))}"
end
