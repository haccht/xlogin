require 'io/console'
require 'net/telnet'
require 'xlogin/session'

module Xlogin
  class Telnet < Net::Telnet

    prepend SessionModule

    def initialize(args)
      username = args.delete('Username')
      password = args.delete('Password')

      super(args)
      login(*[username, password].compact) if username || password
    end

    def interact!
      $stdin.raw!
      enable_log($stdout)

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

            raise EOFError if bs == "\u001D" # <Ctrl-]> to force quit
            @sock.syswrite(bs)
          when @sock
            begin
              write_log(fh.readpartial(1024))
            rescue Errno::EAGAIN
              retry
            end
          end
        end
      end
    rescue EOFError, Errno::ECONNRESET
      $stdout.puts "\r\n", "Conneciton closed.", "\r\n"
      close
    ensure
      $stdin.cooked!
    end

  end
end
