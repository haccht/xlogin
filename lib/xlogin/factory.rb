require 'singleton'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @database  = Hash.new
      @templates = Hash.new
      @group     = nil
    end

    def source(*files)
      files.compact.each do |file|
        file = File.expand_path(file)
        instance_eval(IO.read(file)) if File.exist?(file)
      end
    end

    def set(**params)
      name = params[:name]
      @database[name] = params if name
    end

    def get(name)
      @database[name]
    end

    def list(name = nil)
      keys = @database.keys
      keys = keys.select { |key| key =~ /^#{name}(:|$)/ } unless name.nil? || name.to_s == 'all'
      @database.values_at(*keys)
    end

    def source_template(*files)
      files.compact.each do |file|
        file = File.expand_path(file)
        name = File.basename(file, '.rb').scan(/\w+/).join('_')
        next unless File.exist?(file)

        set_template(name, IO.read(file))
      end
    end

    def set_template(name, text)
      template = get_template(name)
      template.instance_eval(text)
      @templates[name.to_s.downcase] = template
    end

    def get_template(name)
      @templates[name.to_s.downcase] ||= Xlogin::Template.new(name)
    end

    def list_templates
      @templates.keys
    end

    def group(group_name)
      current_group = @group
      @group = [current_group, group_name.to_s].compact.join(':')
      yield
      @group = current_group
    end

    def build(type:, uri:, **params)
      template = get_template(type)
      raise Xlogin::TemplateError.new("Template not found: '#{type}'") unless template

      template.build(uri, **params)
    end

    def build_from_hostname(hostname, **params)
      hostinfo = get(hostname)
      raise Xlogin::SessionError.new("Host not found: '#{hostname}'") unless hostinfo

      build(hostinfo.merge(**params)).tap { |s| s.name = hostname }
    end

    def method_missing(method_name, *args, &block)
      super unless caller_locations.first.label == 'block in source' and args.size >= 2

      type = method_name.to_s.downcase
      name = [@group, args.shift].compact.join(':')
      uri  = args.shift
      opts = args.shift || {}
      set(type: type, name: name, uri: uri, **opts)
    end

  end
end
