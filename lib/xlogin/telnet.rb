require 'io/console'
require 'net/telnet'
require 'xlogin/session'

module Xlogin
  class Telnet < Net::Telnet

    include Session

    def initialize(**opts)
      configure_session(opts.merge(port: opts[:port] || 23))

      super(
        'Host'    => @node,
        'Port'    => @port,
        'Timeout' => @timeout,
        'Prompt'  => Regexp.union(*@prompts.map(&:first))
      )

      login(*@userinfo) if respond_to?(:login) && !@userinfo.empty?
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
      $stdin.raw!
      disable_log($stdout)

      loop do
        rs, _ = IO.select([$stdin, @sock])
        rs.each do |fh|
          case fh
          when $stdin
            bs = ''
            begin
              bs = fh.read_nonblock(1)
              if bs == "\e"
                bs << fh.read_nonblock(3)
                bs << fh.read_nonblock(2)
              end
            rescue IO::WaitReadable
            end

            raise EOFError if bs == "\u001D" # <Ctrl-]> for quit
            @sock.syswrite(bs)
          when @sock
            begin
              bs = fh.readpartial(1024)
              $stdout.syswrite(bs)
              @logger.call(bs)
            rescue Errno::EAGAIN
              retry
            end
          end
        end
      end
    rescue EOFError
      $stdout.puts "\r\n", "Conneciton closed."
      self.close
    ensure
      $stdin.cooked!
    end

  end
end
