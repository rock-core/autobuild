require "bundler/gem_tasks"
require "rake/testtask"

task 'default'
task 'gem' => 'build'

Rake::TestTask.new(:test) do |t|
    t.libs << "lib" << Dir.pwd
    t.test_files = ['test/suite.rb']
end

