# xlogin

rancid clogin alternative.  
xlogin is a tool to login devices and execute series of tasks.

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

Write a template file that describe how to login to the specific type of device, and store it to `~/.xlogin.d/`.  
Take vyos as an example, template file would be:

```ruby
prompt(/[$#] (?:\e\[K)?\z/n)

login do |username, password|
  waitfor(/login:\s/)    && puts(username)
  waitfor(/Password:\s/) && puts(password)
  waitfor
end
```

Some other example are in [lib/xlogin/templates](https://github.com/haccht/xlogin/tree/master/lib/xlogin/templates).

Beside template files, you need to prepare an inventory file `~/.xloginrc`.
In this file, you need to write all information required to login each device.

```
#hosttype	hostname	uri scheme
vyos	'vyos01',	'telnet://vagrant:vagrant@127.0.0.1:2200'
vyos	'vyos02',	'telnet://vagrant:vagrant@127.0.0.1:2201'
```

Now you can login any device in your `.xloginrc` file with a command:

```sh
xlogin vyos01
```

And execute multiple operations with just a single command:

~~~sh
xlogin 'vyos*' -e 'show configuration command | no-more; exit' -j 2
~~~

Some other commandline options are:

~~~sh
$ xlogin -h
xlogin HOST_PATTERN [Options]
    -i, --inventory PATH             The PATH to the inventory file(default: $HOME/.xloginrc).
        --template PATH              The PATH to the template file.
    -T, --template-dir DIRECTORY     The DIRECTORY of the template files.
    -L, --log-dir [DIRECTORY]        The DIRECTORY of the log files(default: $PWD).
    -l, --list                       List all available devices.
    -e, --exec                       Execute commands and quit.
    -t, --tty                        Allocate a pseudo-tty.
    -p, --port NUM                   Run as server on specified port(default: 8080).
    -j, --jobs NUM                   The NUM of jobs to execute in parallel(default: 1).
    -E, --enable                     Try to gain enable priviledge.
    -y, --assume-yes                 Automatically answer yes to prompts.
~~~

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/xlogin. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

