# xlogin

xlogin is a tool to login devices and execute series of commands with ease.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'xlogin'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install xlogin

## Usage

Write a firmware template that describe how to manage the device, and store it to `~/.xlogin.d/`.  
Be aware that the name of the template file should match the hosttype of the device in the inventory file.  
Take vyos as an example, template file `vyos.rb` would be:

```ruby
prompt(/[$#] (?:\e\[K)?\z/n)

login do |username, password|
  waitfor(/login:\s/)    && puts(username)
  waitfor(/Password:\s/) && puts(password)
  waitfor
end
```

Some other example templates are in [lib/xlogin/templates](https://github.com/haccht/xlogin/tree/master/lib/xlogin/templates).  
You can just load these built-in templates by adding `require "xlogin/template"` in your script.

Beside template files, you should have your own inventory file `~/.xloginrc` that list all information required to login each devices.

```
#hosttype	hostname	uri scheme
vyos	'vyos01',	'telnet://vagrant:vagrant@127.0.0.1:2200'
vyos	'vyos02',	'telnet://vagrant:vagrant@127.0.0.1:2201'
```

Now you can login to the device in your `.xloginrc` file.

```sh
$ xlogin vyos01
```

And execute multiple operations with just a single command.

~~~sh
$ xlogin 'vyos*' -e 'show configuration command | no-more; exit' -j 2
~~~

Some other commandline options are:

~~~sh
$ xlogin -h
xlogin HOST_PATTERN [Options]
    -i, --inventory PATH             The PATH to the inventory file.
    -t, --template PATH              The PATH to the template file or directory.
    -L, --log-dir PATH               The PATH to the log directory.
    -l, --list                       List the inventory.
    -e, --exec COMMAND               Execute commands and quit.
    -E, --env KEY=VAL                Environment variables.
    -j, --jobs NUM                   The NUM of jobs to execute in parallel.
~~~

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/xlogin. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

