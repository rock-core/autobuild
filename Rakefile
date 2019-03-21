require "bundler/gem_tasks"
require "rake/testtask"

task 'default'
task 'gem' => 'build'

Rake::TestTask.new(:test) do |t|
    t.libs << "lib" << Dir.pwd

    test_files = Rake::FileList['test/**/test_*.rb']
    test_files.exclude('test/import/test_cvs.rb') unless File.executable?('/usr/bin/cvs')
    t.test_files = test_files
end
