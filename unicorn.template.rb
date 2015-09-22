base_dir = "/home/#{ENV['USER']}/apps/ginger"

listen 4567
working_directory "#{base_dir}/current"
pid "#{base_dir}/unicorn.pid"
worker_processes 15