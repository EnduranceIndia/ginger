# set path to app that will be used to configure unicorn,
# note the trailing slash in this example
@dir = '/path/to/ginger/'

worker_processes 1
working_directory @dir

timeout 30

# Set process id path
pid "#{@dir}unicorn.pid"

# Set log file paths
stderr_path "#{@dir}log/unicorn.stderr.log"
stdout_path "#{@dir}log/unicorn.stdout.log"