require 'net/ssh/telnet'
require 'xlogin/session'

module Xlogin
  class Ssh < Net::SSH::Telnet

    include Session

    def initialize(**opts)
      configure_session(opts.merge(port: opts[:port] || 22))
      username, password = @userinfo.split(':')

      super(
        'Host'     => @host,
        'Port'     => @port,
        'Username' => username,
        'Password' => password,
        'Timeout'  => @timeout,
        'Prompt'   => Regexp.union(*@prompts.map(&:first))
      )
    end

    def interact!
      raise 'Not implemented'
    end

  end
end
