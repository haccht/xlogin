$:.unshift File.dirname(__FILE__)

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

    def source(*source_files, &block)
      return source_file(*source_files) unless block
      factory.instance_eval(&block) unless source_files.empty?
    end

    def source_file(*source_files)
      source_files.compact.each do |file|
        raise SessionError.new("Inventory file not found: #{file}") unless File.exist?(file)
        factory.instance_eval(IO.read(file), file) if File.exist?(file)
      end
    end

    def template(name, *args, &block)
      return template_dir(name, *args) unless block

      raise ArgumentError.new('missing template name') unless name
      factory.set_template(name, &block)
    end

    def template_file(*template_files)
      template_files.compact.each do |file|
        raise TemplateError.new("Template file not found: #{file}") unless File.exist?(file)
        name = File.basename(file, '.rb').scan(/\w+/).join('_')
        factory.set_template(name, IO.read(file)) if File.exist?(file)
      end
    end

    def template_dir(*template_dirs)
      files = template_dirs.flat_map { |dir| Dir.glob(File.join(dir, '*.rb')) }
      template_file(*files)
    end

  end

end
