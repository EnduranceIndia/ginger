require "#{BASE}/config_#{ENV['RACK_ENV']}"

CONF = env_conf

def get_conf
  CONF
end
