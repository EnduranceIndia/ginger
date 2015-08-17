def env_conf
	{
			'datasources' => {
					'mysql-database' => {
							'type' => 'mysql',
							'hostname' => 'localhost',
							'username' => 'root',
							'password' => 's7a'
					},

					'postgres-database' => {
							'type' => 'postgresql',
							'hostname' => 'localhost',
							'username' => 'postgres',
							'password' => 's7a'
					}
			},

			'base_files_directory' => 'files/' # must contain subdirectories named 'pages' and 'cache'. The application must be able to read and write files in those directories
	}
end
