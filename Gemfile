source 'https://rubygems.org'

gemspec

group :lint do
    # base64/ostruct are not part of the default gems since ruby 3.4 resp. 4.0
    # required by rubocop, can be removed when increasing rubocop version
    gem 'base64'
    gem 'ostruct'
    gem 'parallel', '1.24.0'
    gem 'rubocop', '1.28.2'
    gem 'rubocop-ast', '1.17.0'
    gem 'rubocop-rock'
end

group :vscode do
    gem 'debase', '>= 0.2.2.beta10'
    gem 'pry'
    gem 'pry-byebug'
    gem 'ruby-debug-ide', '>= 0.6.0'
    gem 'solargraph'
end
