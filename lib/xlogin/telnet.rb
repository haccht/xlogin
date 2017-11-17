require 'io/console'
require 'net/telnet'
require 'xlogin/session'

module Xlogin
  class Telnet < Net::Telnet

    prepend SessionModule

    alias_method :telnet_login, :login
    undef_method :login

    def initialize(params)
      username = params.delete('Username')
      password = params.delete('Password')
      super(params)

      if username || password
        return login(*[username, password].compact) if respond_to?(:login)
        telnet_login(*[username, password].compact)
      end
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
              bs = fh.readpartial(1024)
              output_log(bs)
            rescue Errno::EAGAIN
              retry
            end
          end
        end
      end
    rescue EOFError, Errno::ECONNRESET
      $stdout.puts "\r\n", "Conneciton closed.", "\r\n"
      self.close
    ensure
      $stdin.cooked!
    end

  end
end
