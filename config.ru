require 'rubygems'
require 'sinatra'

require File.dirname(__FILE__) + '/index.rb'

require 'logger'
logger = Logger.new('logs/application.log', shift_age=7, shift_size = 1024 * 1024 * 10)

use Rack::CommonLogger, logger

run Sinatra::Application
