def env_conf
{
	:data_sources => {
		:mysql_database => {
			:type => 'mysql',
			:hostname => 'localhost',
			:username => 'root',
			:password => 's7a'
		},

		:postgres_database => {
			:type => 'postgresql',
			:hostname => 'localhost',
			:username => 'postgres',
			:password => 's7a'
		}
	},

	:base_files_directory => 'files/' # must contain subdirectories named 'pages' and 'cache'. The application must be able to read and write files in those directories
}
end
