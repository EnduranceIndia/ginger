def format(connection, value, type)
	return escape(connection, value) if type == 'string'
	value
end

def escape(connection, value)
	"#{strip_quotes(connection.escape(value))}"
end
