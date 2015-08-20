def env_conf
  {
    :authentication => {
      :example_com => {
        :type => 'ldap',
        :ldap_server => 'ldap.example.com',
        :ldap_port => 389
      }
    },

    :base_files_directory => 'files/' # must contain subdirectories named 'pages' and 'cache'. The application must be able to read and write files in those directories
  }
end
