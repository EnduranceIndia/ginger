def format(connection, value, type)
  return escape(connection, value) if type == 'string'
  value
end

def escape(connection, value)
  "#{strip_quotes(connection.escape(value))}"
end

def permissions_hash_to_string(permissions_hash)
  permissions_string = ''

  permissions_hash.each do |name, permission|
    permissions_string += "#{name}=#{permission};"
  end

  permissions_string
end

def permissions_string_to_hash(permissions_string)
  permissions_hash = {}

  permissions_string.split(';').each do |permission|
    permission_literals = permission.split('=')
    permissions_hash[param_to_sym(permission_literals.first)] = permission_literals.last
  end

  permissions_hash
end

def get_highest_permission(permissions_list)
  permissions_priority = {
      :forbidden => 0,
      :read => 1,
      :preview => 2,
      :write => 3
  }

  current_permission = 'forbidden'

  permissions_list.each do |perm|
    permission = perm[:permission]
    if permissions_priority[param_to_sym(permission)] > permissions_priority[param_to_sym(current_permission)]
      current_permission = permission
    end
  end

  current_permission
end