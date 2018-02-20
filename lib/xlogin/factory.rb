require 'singleton'
require 'thread'
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
        path = File.expand_path(file, ENV['PWD'])
        raise SessionError.new("File not found: #{file}") unless File.exist?(path)

        instance_eval(IO.read(path))
      end
    end

    def set(**opts)
      name = opts[:name]
      @database[name] = (get(name) || {}).merge(opts) if name
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
        path = File.expand_path(file, ENV['PWD'])
        name = File.basename(path, '.rb').scan(/\w+/).join('_')
        raise TemplateError.new("File not found: #{file}") unless File.exist?(path)

        set_template(name, IO.read(path))
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

    def build(type:, uri:, **opts)
      template = get_template(type)
      template.build(uri, **opts)
    end

    def build_from_hostname(hostname, **opts)
      hostinfo = get(hostname)
      raise Xlogin::SessionError.new("Host not found: '#{hostname}'") unless hostinfo

      build(hostinfo.merge(name: hostname, **opts))
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
