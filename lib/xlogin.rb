$:.unshift File.dirname(__FILE__)

require 'xlogin/factory'
require 'xlogin/session_pool'
require 'xlogin/version'

module Xlogin

  class SessionError       < StandardError; end
  class TemplateError      < StandardError; end
  class AuthorizationError < StandardError; end

  class << self

    def factory
      @factory ||= Xlogin::Factory.instance
    end

    def get(args, **opts, &block)
      session = case args
                when Hash   then factory.build(**args.merge(**opts))
                when String then factory.build_from_hostname(args, **opts)
                end

      return session unless block
      begin block.call(session) ensure session.close end
    end

    def get_pool(args, **opts, &block)
      pool = Xlogin::SessionPool.new(args, **opts)

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

    def source(*source_files)
      factory.source(*source_files)
    end

    def template(*template_dirs)
      files = template_dirs.flat_map { |dir| Dir.glob(File.join(dir, '*.rb')) }
      load_templates(*files)
    end
    alias_method :template_dir, :template

    def load_templates(*template_files)
      factory.source_template(*template_files)
    end

  end

end
