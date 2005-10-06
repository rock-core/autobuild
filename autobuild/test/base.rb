$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'rubygems'
require 'test/unit'
require 'test/tc_config_interpolation.rb'
require 'test/tc_config.rb'
require 'test/tc_subcommand.rb'
require 'test/tc_import.rb'
