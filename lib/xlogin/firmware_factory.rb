require 'uri'
require 'singleton'
require 'stringio'
require 'xlogin/firmware'

module Xlogin
  class FirmwareFactory

    include Singleton

    def initialize
      @database  = Hash.new
      @templates = Hash.new
    end

    def load_template_file(file)
      require file if file =~ /.rb$/
    end

    def get_template(name)
      @templates[name.to_s.downcase]
    end

    def set_template(name, template)
      @templates[name.to_s.downcase] = template
    end

    def list_templates
      @templates.keys
    end

    def source(db_file)
      return unless File.exist?(db_file)

      content = IO.read(db_file)
      instance_eval(content)
    end

    def get(name)
      @database[name]
    end

    def set(**opts)
      @database[opts[:name]] = opts
    end

    def list
      @database.values
    end

    def build(args)
      uri  = args.delete(:uri)
      type = args.delete(:type)
      name = args.delete(:name)
      opts = args.reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }
      raise Xlogin::GeneralError.new("Host not found: #{args}") unless uri && type

      session = get_template(type).dup.run(uri, opts)
      session.name = name if name
      session
    end

    def build_from_hostname(hostname, **args)
      host = get(hostname)
      raise Xlogin::GeneralError.new("Host not found: #{hostname}") unless host

      build(get(hostname).merge(args))
    end

    def method_missing(name, *args, &block)
      super unless caller_locations.first.label == "source"

      type = name.to_s.downcase
      name = args.shift
      uri  = args.shift
      opts = args.shift || {}
      set(type: type, name: name, uri: uri, **opts)
    end

  end
end
