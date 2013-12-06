def get_conf
	{
		'datasources' => {
			'localhost' => {
				'type' => 'mysql',
				'hostname' => 'localhost',
				'username' => 'user',
				'password' => '12345'
			}
		},

		'base_files_directory' => '/1/2/3' # must contain subdirectories named 'pages' and 'cache'. The application must be able to read and write files in those directories
	}
end
