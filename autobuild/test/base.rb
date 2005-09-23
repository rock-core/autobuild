$LOAD_PATH << File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH << File.expand_path(File.dirname(__FILE__))
require 'rubygems'
require 'test/unit'
require 'tc_config_interpolation.rb'
require 'tc_config.rb'
require 'tc_subcommand.rb'
require 'tc_import.rb'
