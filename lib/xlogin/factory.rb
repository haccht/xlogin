require 'addressable/uri'
require 'singleton'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @inventory = Hash.new
      @templates = Hash.new
    end

    def set_inventory(**opts)
      return unless name = opts[:name]
      @inventory[name] = (get_inventory(name) || {}).merge(opts)
    end

    def get_inventory(name)
      @inventory[name]
    end

    def list_inventory(*patterns)
      return @inventory.values if patterns.empty?

      values = patterns.map do |pattern|
        key, val = pattern.to_s.split(':')
        key, val = 'name', key if val.nil?
        val.split(',').map { |e| @inventory.values.select { |info| File.fnmatch(e, info[key.to_sym]) } }.reduce(&:|)
      end
      values.reduce(&:&).uniq
    end

    def set_template(name, text = nil, &block)
      template = get_template(name)
      template.instance_eval(text)   if text
      template.instance_eval(&block) if block
      @templates[name.to_s.downcase] = template
    end

    def get_template(name)
      @templates[name.to_s.downcase] ||= Xlogin::Template.new(name)
    end

    def list_templates
      @templates.keys
    end

    def build(type:, **opts)
      template = get_template(type)
      if opts[:uri]
        template.build(opts[:uri], **opts)
      else
        scheme   = opts[:scheme]
        address  = opts.values_at(:host, :port).compact.join(':')
        userinfo = opts[:userinfo]
        userinfo ||= opts.values_at(:username, :password).compact.join(':')

        template.build("#{scheme}://" + [userinfo, address].compact.join('@'), **opts)
      end
    end

    def build_from_hostname(args, **opts)
      hostinfo = get_inventory(args)
      raise SessionError.new("Host not found: '#{args}'") unless hostinfo

      build(hostinfo.merge(name: args, **opts))
    end

    def build_pool(args, **opts)
      Xlogin::SessionPool.new(args, **opts)
    end

  end
end
