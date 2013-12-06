def get_conf
	conf = {
		'datasources' => {}
	}

	require "./config_#{ENV['RACK_ENV']}"

	env_conf(conf)

	if conf['datasources'].keys.length == 0
		raise "At least one data sources must be configured."
	elsif !conf.has_key?('base_files_directory')
		raise "base_files_directory must be configured. It must contain subdirectories named 'pages' and 'cache', and the application must be able to create and read files in them."
	end

	return conf
end
