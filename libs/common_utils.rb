def format(connection, value, type)
	return "#{connection.escape(value)}" if type == 'string'
	return value
end
