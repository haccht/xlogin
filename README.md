# xlogin
rancid clogin alternative.

## Usage

ネットワークデバイスへのログインを自動化するツール群。  
`xlogin/firmares`にファームウェア仕様を記述することで対象機器を拡大可能。


各個別装置毎のログインのための認証情報は`~/.xloginrc`へ記述しておく。  
`.xloginrc`のフォーマットはDSL形式で下記の通り

~~~
#hosttype	hostname	telnet_uri_scheme	options
vyos	'vyos01',	'telnet://vagrant:vagrant@127.0.0.1:2200'
vyos	'vyos02',	'telnet://vagrant:vagrant@127.0.0.1:2201'
~~~

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'xlogin'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install xlogin

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/xlogin. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

