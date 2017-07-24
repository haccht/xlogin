require 'net/ssh/telnet'
require 'xlogin/session'

module Xlogin
  class Ssh < Net::SSH::Telnet

    include Session

    def initialize(**opts)
      configure_session(opts.merge(port: opts[:port] || 22))
      username, password = @userinfo

      super(
        'Host'     => @host,
        'Port'     => @port,
        'Username' => username,
        'Password' => password,
        'Timeout'  => @timeout,
        'Prompt'   => Regexp.union(*@prompts.map(&:first))
      )
    end

    def waitfor(*expect)
      if expect.compact.empty?
        super(Regexp.union(*@prompts.map(&:first)), &@logger)
      else
        line = super(*expect, &@logger)
        _, process = @prompts.find { |r, p| r =~ line && p }
        if process
          instance_eval(&process)
          line += waitfor(*expect)
        end
        line
      end
    end

    def interact!
      raise 'Not implemented'
    end

  end
end
