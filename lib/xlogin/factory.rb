require 'singleton'
require 'thread'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @database  = Hash.new
      @templates = Hash.new
    end

    def source(*files)
      files.compact.each do |file|
        raise SessionError.new("Inventory file not found: #{file}") unless File.exist?(file)
        instance_eval(IO.read(file)) if File.exist?(file)
      end
    end

    def set(**opts)
      name = opts[:name]
      @database[name] = (get(name) || {}).merge(opts) if name
    end

    def get(name)
      @database[name]
    end

    def list(pattern = nil)
      key, val = pattern.to_s.split(':')
      key, val = 'name', (key || '*') if val.nil?
      val.split(',').map { |e| @database.values.select { |info| File.fnmatch(e, info[key.to_sym]) } }.reduce(&:|)
    end

    def source_template(*files)
      files.compact.each do |file|
        raise TemplateError.new("Template file not found: #{file}") unless File.exist?(file)
        name = File.basename(file, '.rb').scan(/\w+/).join('_')
        set_template(name, IO.read(file)) if File.exist?(file)
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
      name = args.shift
      uri  = args.shift
      opts = args.shift || {}
      set(type: type, name: name, uri: uri, **opts)
    end

  end
end
