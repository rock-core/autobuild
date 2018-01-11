require "bundler/gem_tasks"
require "rake/testtask"

task 'default'
task 'gem' => 'build'

Rake::TestTask.new(:test) do |t|
    t.libs << "lib" << Dir.pwd

    test_files = Rake::FileList['test/**/test_*.rb']
    if !File.executable?('/usr/bin/cvs')
        test_files.exclude('test/import/test_cvs.rb')
    end
    t.test_files = test_files
end

