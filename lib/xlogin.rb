$:.unshift File.dirname(__FILE__)

require 'net/http'
require 'ostruct'
require 'xlogin/factory'
require 'xlogin/version'

module Xlogin

  class Error < StandardError; end
  class ReadOnlyStruct < OpenStruct
    def initialize(*args, &block)
      super(*args, &block)
      freeze
    end

    def method_missing(name, *args, &block)
      return to_h.key?($1.to_sym) if name.to_s =~ /^(\w+)\?$/
      super(name, *args, &block)
    end
  end

  class << self
    def find(*patterns)
      list(*patterns).first
    end

    def list(*patterns)
      factory.list_hostinfo(*patterns)
    end

    def get(args = nil, **opts, &block)
      case args
      when nil    then factory.build(**opts, &block)
      when String then factory.build_from_hostname(args, **opts, &block)
      else
        raise Xlogin::Error.new("Invalid argument: '#{args}'")
      end
    end

    def pool(args, **opts, &block)
      factory.build_pool(args, **opts, &block)
    end

    def configure(&block)
      instance_eval(&block)
    end

    def settings
      ReadOnlyStruct.new(@settings || {})
    end

    def generate_templates(dir)
      FileUtils.mkdir_p(dir)
      builtin_templates = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))
      builtin_templates.each{ |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
    end

    def factory
      @factory ||= Xlogin::Factory.instance
    end

    private
    def set(opts = {})
      @settings ||= {}
      opts.each do |key, val|
        val = val.call if val.kind_of?(Proc)
        @settings.update(key.to_sym => val)
      end
    end

    def source(*sources, &block)
      return factory.instance_eval(&block) if block && sources.size == 0

      sources.each do |path|
        raise Xlogin::Error.new("Inventory file not found: #{path}") unless File.exist?(path)
        factory.instance_eval(IO.read(path), path)
      end
    end

    def template(*templates, **opts, &block)
      return factory.set_template(templates.shift, &block) if block && templates.size == 1

      templates.each do |template|
        return template_url(template, **opts) if template =~ %r{^https?://\S+}
        raise Xlogin::Error.new("Template file or directory not found: #{template}") unless File.exist?(template)

        paths = [template] if File.file?(template)
        paths = Dir.glob(File.join(template, '*.rb')) if File.directory?(template)
        paths.each do |path|
          name = opts[:type] || File.basename(path, '.rb').scan(/\w+/).join('_')
          factory.set_template(name, IO.read(path))
        end
      end
    end

    def template_url(*template_urls, **opts)
      template_urls.each do |url|
        uri  = URI(url.to_s)
        name = opts[:type] || File.basename(uri.path, '.rb').scan(/\w+/).join('_')
        factory.set_template(name, Net::HTTP.get(uri))
      end
    end
  end

end
