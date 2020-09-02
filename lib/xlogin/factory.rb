require 'addressable/uri'
require 'net/ssh/gateway'
require 'singleton'
require 'thread'
require 'xlogin/session_pool'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @inventory = Hash.new
      @templates = Hash.new
      @tunnels   = Hash.new
      @mutex     = Mutex.new
    end

    def set_hostinfo(name, **opts)
      @inventory[name] = (get_hostinfo(name) || {name: name}).merge(opts)
    end

    def get_hostinfo(name)
      @inventory[name]
    end

    def list_hostinfo(*patterns)
      return @inventory.values if patterns.empty?

      values1 = patterns.compact.map do |pattern|
        values2 = pattern.split(',').map do |entry|
          key, val = entry.to_s.split(':')
          key, val = 'name', key if val.nil?
          @inventory.values.select{ |e| File.fnmatch(val, e[key.to_sym]) }
        end
        values2.reduce(&:&) || []
      end
      values1.reduce(&:|) || []
    end

    def set_template(name, text = nil, &block)
      template = get_template(name) || Xlogin::Template.new(name)
      template.instance_eval(text)   if text
      template.instance_eval(&block) if block
      @templates[name.to_s.downcase] = template
    end

    def get_template(name)
      @templates[name.to_s.downcase]
    end

    def list_templates
      @templates.keys
    end

    def open_tunnel(name, host, port)
      @mutex.synchronize do
        unless @tunnels[name]
          uri = Addressable::URI.parse(name)
          case uri.scheme
          when 'ssh'
            username, password = *uri.userinfo.split(':')
            gateway = Net::SSH::Gateway.new(
              uri.host,
              username,
              password: password,
              port: uri.port || 22
            )

             @tunnels[name] = Struct.new('Tunnel', :gateway, :ports).new(gateway, [])
          end
        end

        if tunnel = @tunnels[name]
          port = tunnel.gateway.open(host, port)
          host = '127.0.0.1'
          tunnel.ports << port
        end
        return host, port
      end
    end

    def close_tunnel(name, port)
      @mutex.synchronize do
        if tunnel = @tunnels[name]
          tunnel.ports.delete(port)
          tunnel.gateway.close(port)
          tunnel.gateway.shutdown! if tunnel.ports.empty?
        end
      end
    end

    def build(type:, **opts)
      template = get_template(type)
      raise Xlogin::Error.new("Template not found: '#{type}'") unless template

      template.build(uri(opts), **opts)
    end

    def build_pool(args, **opts)
      Xlogin::SessionPool.new(args, **opts)
    end

    def build_from_hostname(args, **opts)
      hostinfo = get_hostinfo(args)
      raise Xlogin::Error.new("Host not found: '#{args}'") unless hostinfo

      build(**hostinfo.merge(**opts))
    end

    def method_missing(method_name, *args, **opts, &block)
      super unless args.size == 2 && Addressable::URI::URIREGEX =~ args[1]

      name = args[0]
      uri  = args[1]
      type = method_name.to_s.downcase
      set_hostinfo(name.to_s, type: type, uri: uri, **opts)
    end

    private
    def uri(**opts)
      return Addressable::URI.parse(opts[:uri].strip) if opts.key?(:uri)
      Addressable::URI.new(**opts)
    rescue
      raise Xlogin::Error.new("Invalid target - '#{opts}'")
    end

  end
end
