require 'uri'
require 'net/ssh/gateway'

module Xlogin
  module Session

    alias_method :original_configure, :configure
    def configure(**opts)
      original_configure(**opts)

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

          @port = @gateway.open(@node, @port)
          @node = '127.0.0.1'
        end
      end
    end
  end

end
