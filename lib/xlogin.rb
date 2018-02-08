$:.unshift File.dirname(__FILE__)

require 'xlogin/factory'
require 'xlogin/version'

module Xlogin

  DEFAULT_INVENTORY_FILE = File.join(ENV['HOME'], '.xloginrc')
  DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')
  BUILTIN_TEMPLATE_FILES = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))

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
      pool = factory.pool(args, **opts)

      return pool unless block
      block.call(pool)
    end

    def configure(&block)
      instance_eval(&block)
    end

    def authorized?
      @authorized == true
    end

    private
    def authorize(boolean = false, &block)
      @authorized = boolean == true || (block && block.call == true)
    end

    def source(source_file = nil)
      factory.source(source_file || DEFAULT_INVENTORY_FILE)
    end

    def template(*template_files)
      return factory.source_template(*template_files) unless template_files.empty?

      unless Dir.exist?(DEFAULT_TEMPLATE_DIR)
        FileUtils.mkdir_p(DEFAULT_TEMPLATE_DIR)
        BUILTIN_TEMPLATE_FILES.each { |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
      end
      template_dir(DEFAULT_TEMPLATE_DIR)
    end

    def template_dir(*template_dirs)
      files = template_dirs.flat_map { |dir| Dir.glob(File.join(dir, '*.rb')) }
      template(*files)
    end

  end

end
