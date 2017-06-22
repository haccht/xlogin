begin
  require 'uri'
  require 'net/ssh/gateway'

  module Xlogin
    module Session

      alias_method :original_configure_session, :configure_session
      def configure_session(**opts)
        original_configure_session(**opts)

        if uri = opts[:via]
          gateway = URI(uri)
          username, password = *gateway.userinfo.split(':')

          case gateway.scheme
          when 'ssh'
            @gateway = Net::SSH::Gateway.new(
              gateway.host,
              username,
              password: password,
              port: gateway.port || 22
            )

            @port = @gateway.open(@host, @port)
            @host = '127.0.0.1'
          end
        end
      end
    end

  end
rescue LoadError
  $stderr.puts "Option 'gateway' is not supported in your environment."
end
