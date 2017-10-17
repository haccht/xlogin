$:.unshift File.dirname(__FILE__)

require 'xlogin/factory'
require 'xlogin/version'

module Xlogin

  DEFAULT_INVENTORY_FILE = File.join(ENV['HOME'], '.xloginrc')
  DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')
  BUILTIN_TEMPLATE_FILES = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))

  class SessionNotFound    < StandardError; end
  class TemplateNotFound   < StandardError; end
  class AuthorizationError < StandardError; end

  class << self

    def factory
      @factory ||= Xlogin::Factory.instance
    end

    def get(hostname, args = {})
      session = factory.build_from_hostname(hostname, args)

      if block_given?
        begin yield session ensure session.close end
      else
        session
      end
    end

    def configure(&block)
      instance_eval(&block) if block

      source(DEFAULT_INVENTORY_FILE) if factory.list.empty?
      if factory.list_templates.empty?
        unless Dir.exist?(DEFAULT_TEMPLATE_DIR)
          FileUtils.mkdir_p(DEFAULT_TEMPLATE_DIR)
          Xlogin::BUILTIN_TEMPLATE_FILES.each { |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
        end
        template_dir(DEFAULT_TEMPLATE_DIR)
      end
    end

    def authorized?
      @authorized == true
    end

    private
    def authorize(boolean = false, &block)
      @authorized = boolean == true || (block && block.call == true)
    end

    def source(source_file)
      factory.source(source_file)
    end

    def template(*template_files)
      factory.set_template(*template_files)
    end

    def template_dir(*template_dirs)
      template_dirs.each do |template_dir|
        template(*Dir.glob(File.join(template_dir, '*.rb')))
      end
    end

  end

end
