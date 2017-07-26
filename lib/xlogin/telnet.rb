require 'io/console'
require 'net/telnet'
require 'xlogin/session'

module Xlogin
  class Telnet < Net::Telnet

    include Session

    def initialize(**opts)
      configure_session(opts.merge(port: opts[:port] || 23))

      super(
        'Host'    => @host,
        'Port'    => @port,
        'Timeout' => @timeout,
        'Prompt'  => Regexp.union(*@prompts.map(&:first))
      )

      login(*@userinfo.split(':')) if respond_to?(:login) && !@userinfo.empty?
    end

    def renew(opts = @opts)
      self.class.new(opts).tap { |s| @sock = s.sock }
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
    rescue EOFError, Errno::ECONNRESET
      $stdout.puts "\r\n", "Conneciton closed."
      self.close
    ensure
      $stdin.cooked!
    end

  end
end
