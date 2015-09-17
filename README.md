## What's autobuild ?

Autobuild is a collection of classes to interface with build systems (e.g.
autotools, CMake) and import mechanisms (git, svn, ...). It is used to build the
[autoproj](http://rock-robotics.org/documentation/autoproj) higher-level tool
that provides mechanisms to manage a whole workspace.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'autobuild'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install autobuild

## Development

After checking out the repo, run `bundle install` to install dependencies. Then,
run `bundle exec rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/rock-core/autobuild

## License

The gem is available as open source under the terms of the GPL license v2 or
later.

Copyright and license
=====================
Author::    Sylvain Joyeux <sylvain.joyeux@m4x.org>
Copyright:: Copyright (c) 2005-2015 Sylvain Joyeux
License::   GPL

