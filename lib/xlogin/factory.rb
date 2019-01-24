require 'addressable/uri'
require 'singleton'
require 'xlogin/session_pool'
require 'xlogin/template'

module Xlogin
  class Factory

    include Singleton

    def initialize
      @inventory    = Hash.new
      @templates    = Hash.new
      @session_pool = Hash.new
    end

    def set_inventory(name, **opts)
      @inventory[name] = (get_inventory(name) || {name: name}).merge(opts)
    end

    def get_inventory(name)
      @inventory[name]
    end

    def list_inventory(*patterns)
      return @inventory.values if patterns.empty?

      values1 = patterns.map do |pattern|
				values2 = pattern.split(',').map do |entry|
					key, val = entry.to_s.split(':')
					key, val = 'name', key if val.nil?
					@inventory.values.select { |e| File.fnmatch(val, e[key.to_sym]) }
				end
				values2.reduce(&:&)
      end
      values1.reduce(&:|)
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

    def build(type:, **opts)
      template = get_template(type)
      raise TemplateError.new("Template not found: '#{type}'") unless template

      template.build(uri(opts), **opts)
    end

    def build_pool(args, **opts)
      uri = case args
            when Hash   then uri(args)
            when String then uri(get_inventory(args))
            else return
            end

      param = opts.map { |k, v| "#{k}=#{v}" }.join('&')
      @session_pool["#{uri}?#{param}"] ||= Xlogin::SessionPool.new(args, **opts)
    end

    def build_from_hostname(args, **opts)
      hostinfo = get_inventory(args)
      raise SessionError.new("Host not found: '#{args}'") unless hostinfo

      build(hostinfo.merge(name: args, **opts))
    end

    private
    def uri(**opts)
      return Addressable::URI.parse(opts[:uri].strip) if opts.key?(:uri)

      scheme   = opts[:scheme].strip
      address  = opts.values_at(:host, :port).compact.map(&:strip).join(':')
      userinfo = opts[:userinfo].strip
      userinfo ||= opts.values_at(:username, :password).compact.map(&:strip).join(':')

      Addressable::URI.parse("#{scheme}://" + [userinfo, address].compact.join('@'))
    rescue
      raise SessionError.new("Invalid target - '#{opts}'")
    end

  end
end
