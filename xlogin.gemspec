# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xlogin/version'

Gem::Specification.new do |spec|
  spec.name          = "xlogin"
  spec.version       = Xlogin::VERSION
  spec.authors       = ["haccht"]
  spec.email         = ["haccht@users.noreply.github.com"]

  spec.summary       = %q{rancid clogin alternative}
  spec.description   = %q{login to any devices with ease.}
  spec.homepage      = "https://github.com/haccht/xlogin"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.4.1"

  spec.add_dependency "net-telnet"
  spec.add_dependency "net-ssh"
  spec.add_dependency "net-ssh-telnet"
  spec.add_dependency "net-ssh-gateway"
  spec.add_dependency "parallel"
  spec.add_dependency "addressable"
  spec.add_dependency "colorize"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
