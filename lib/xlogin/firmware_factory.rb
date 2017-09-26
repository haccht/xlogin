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
      @group     = nil
    end

    def load_template_files(*files)
      files.each do |file|
        file = File.expand_path(file)
        next unless File.exist?(file) && file =~ /.rb$/

        name = File.basename(file, '.rb').scan(/\w+/).join.downcase
        Xlogin.configure(name) { |firmware| firmware.instance_eval(IO.read(file)) }
      end
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
      keys = keys.select { |key| key =~ /^#{name}(:|$)/ } unless name.nil? || name.to_s == 'all'
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
      raise Xlogin::TemplateNotFound.new("template not found: '#{type}'") unless template

      uri  = args.delete(:uri)
      opts = args.reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }
      raise Xlogin::HostNotFound.new("connection not defined: '#{arg}'") unless uri

      template.dup.run(uri, opts)
    end

    def build_from_hostname(hostname, **args)
      hostinfo = get(hostname)
      raise Xlogin::HostNotFound.new("host not found: '#{hostname}'") unless hostinfo

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
