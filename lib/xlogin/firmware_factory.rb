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
      @aliases   = Hash.new
      @group     = nil
    end

    def load_template_files(*files)
      files.each do |file|
        file = File.expand_path(file)
        next unless File.exist?(file) && file =~ /.rb$/
        require file
      end
    end

    def get_template(name)
      name = @aliases[name.to_s.downcase] || name.to_s.downcase
      @templates[name]
    end

    def set_template(name, template)
      name = @aliases[name.to_s.downcase] || name.to_s.downcase
      @templates[name] = template
    end

    def list_templates
      @templates.keys
    end

    def alias_template(new_name, name)
      @aliases[new_name.to_s.downcase] = name.to_s.downcase
    end

    def source(file)
      file = File.expand_path(file)
      return unless File.exist?(file)
      instance_eval(IO.read(file))
    end

    def get(name)
      @database[name]
    end

    def set(**opts)
      @database[opts[:name]] = opts
    end

    def list(name = nil)
      keys = @database.keys
      keys = keys.select { |key| key =~ /^#{name}(:|$)/ } unless name.nil?
      @database.values_at(*keys)
    end

    def group(group_name)
      current_group = @group
      @group = [current_group, group_name].compact.join(':')
      yield
      @group = current_group
    end

    def build(args)
      type = args.delete(:type)
      template = get_template(type)
      raise Xlogin::GeneralError.new("Template not defined: #{type}") unless template

      uri  = args.delete(:uri)
      opts = args.reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }
      raise Xlogin::GeneralError.new("Host not found: #{args}") unless uri

      template.dup.run(uri, opts)
    end

    def build_from_hostname(hostname, **args)
      hostinfo = get(hostname)
      raise Xlogin::GeneralError.new("Host not found: #{hostname}") unless hostinfo

      build(hostinfo.merge(args))
    end

    def method_missing(method_name, *args, &block)
      super unless caller_locations.first.label =~ /source/ and args.size >= 2

      type = method_name.to_s.downcase
      name = [@group, args.shift].compact.join(':')
      uri  = args.shift
      opts = args.shift || {}
      set(type: type, name: name, uri: uri, **opts)
    end

  end
end
