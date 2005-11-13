$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
require 'rubygems'
require 'test/unit'
require 'test/test_config_interpolation.rb'
require 'test/test_config.rb'
require 'test/test_subcommand.rb'
require 'test/test_import.rb'
