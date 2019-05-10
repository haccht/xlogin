$:.unshift File.dirname(__FILE__)

require 'net/http'
require 'xlogin/factory'
require 'xlogin/version'

module Xlogin

  class SessionError       < StandardError; end
  class TemplateError      < StandardError; end
  class AuthorizationError < StandardError; end

  class << self

    def factory
      @factory ||= Xlogin::Factory.instance
    end

    def list(*patterns)
      factory.list_inventory(*patterns)
    end

    def find(*patterns)
      list(*patterns).first
    end

    def get(args, **opts, &block)
      session = case args
                when Hash   then factory.build(**args.merge(**opts))
                when String then factory.build_from_hostname(args, **opts)
                else return
                end

      return session unless block
      begin block.call(session) ensure session.close end
    end

    def get_pool(args, **opts, &block)
      pool = factory.build_pool(args, **opts)

      return pool unless block
      block.call(pool)
    end

    def configure(&block)
      instance_eval(&block)
    end

    def authorized?
      @authorized == true
    end

    def generate_templates(dir)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      builtin_templates = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))
      builtin_templates.each { |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
    end

    private
    def authorize(boolean = true, &block)
      @authorized = boolean == true || (block && block.call == true)
    end

    def source(*sources, &block)
      unless block
        return sources.each do |path|
          raise SessionError.new("Inventory file not found: #{path}") unless File.exist?(path)
          factory.instance_eval(IO.read(path), path)
        end
      end

      factory.instance_eval(&block)
    end

    def template(*templates, **opts, &block)
      unless block
        templates.each do |template|
          return template_url(template, **opts) if template =~ URI.regexp(['http', 'https'])
          raise TemplateError.new("Template file or directory not found: #{template}") unless File.exist?(template)

          files = [template] if File.file?(template)
          files = Dir.glob(File.join(template, '*.rb')) if File.directory?(template)
          files.each do |file|
            name = opts[:type] || File.basename(file, '.rb').scan(/\w+/).join('_')
            factory.set_template(name, IO.read(file))
          end
        end
      end

      name = opts[:type] || templates.first
      raise ArgumentError.new('Missing template name') unless name
      factory.set_template(name, &block)
    end

    def template_url(*template_urls, **opts)
      template_urls.compact.each do |url|
        uri = URI(url.to_s)
        name = opts[:type] || File.basename(uri.path, '.rb').scan(/\w+/).join('_')
        text = Net::HTTP.get(uri)
        if text =~ /\w+.rb$/
          uri.path = File.join(File.dirname(uri.path), text.lines.first.chomp)
          text = Net::HTTP.get(uri)
        end
        factory.set_template(name, text)
      end
    end

  end

end
