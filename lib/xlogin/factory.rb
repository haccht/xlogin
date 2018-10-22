require 'singleton'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @inventory = Hash.new
      @templates = Hash.new
    end

    def source(*files)
      files.compact.each do |file|
        raise SessionError.new("Inventory file not found: #{file}") unless File.exist?(file)
        instance_eval(IO.read(file), file) if File.exist?(file)
      end
    end

    def set_info(**opts)
      name = opts[:name]
      return unless name
      @inventory[name] = (get_info(name) || {}).merge(opts)
    end

    def get_info(name)
      @inventory[name]
    end

    def list_info(*patterns)
      return @inventory.values if patterns.empty?

      values = patterns.map do |pattern|
        key, val = pattern.to_s.split(':')
        key, val = 'name', key if val.nil?
        val.split(',').map { |e| @inventory.values.select { |info| File.fnmatch(e, info[key.to_sym]) } }.reduce(&:|)
      end
      values.reduce(&:&).uniq
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
      hostinfo = get_info(hostname)
      raise Xlogin::SessionError.new("Host not found: '#{hostname}'") unless hostinfo

      build(hostinfo.merge(name: hostname, **opts))
    end

    def method_missing(method_name, *args, &block)
      super unless caller_locations.first.label == 'block in source' and args.size >= 2

      type = method_name.to_s.downcase
      name = args.shift
      uri  = args.shift
      opts = args.shift || {}

      super if [type, name, uri].any? { |e| e.nil? }
      set_info(type: type, name: name, uri: uri, **opts)
    end

  end
end
