CONF = {}

require "#{BASE}/config_#{ENV['RACK_ENV']}"

CONF = env_conf

if CONF['datasources'].keys.length == 0
	raise "At least one data sources must be configured."
elsif !CONF.has_key?('base_files_directory')
	raise "base_files_directory must be configured. It must contain subdirectories named 'pages' and 'cache', and the application must be able to create and read files in them."
end

def get_conf
	return CONF
end
