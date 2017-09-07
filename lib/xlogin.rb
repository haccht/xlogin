$:.unshift File.dirname(__FILE__)

require 'xlogin/firmware'
require 'xlogin/firmware_factory'
require 'xlogin/version'

module Xlogin

  DEFAULT_SOURCE_FILE    = File.join(ENV['HOME'], '.xloginrc')
  DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')
  BUILTIN_TEMPLATE_FILES = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))

  class GeneralError < StandardError; end

  class << self

    def init(&block)
      instance_eval(&block)

      factory = Xlogin::FirmwareFactory.instance
      factory.source(DEFAULT_SOURCE_FILE) if factory.list.empty?
      if factory.list_templates.empty?
        unless File.exist?(DEFAULT_TEMPLATE_DIR)
          FileUtils.mkdir_p(DEFAULT_TEMPLATE_DIR)
          Xlogin::BUILTIN_TEMPLATE_FILES.each { |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
        end
        factory.load_template_files(*Dir.glob(File.join(DEFAULT_TEMPLATE_DIR, '*.rb')))
      end
    end

    def source(source_file)
      factory = Xlogin::FirmwareFactory.instance
      factory.source(source_file)
    end

    def template(*template_files)
      factory = Xlogin::FirmwareFactory.instance
      factory.load_template_files(*template_files)
    end

    def get(hostname, args = {})
      factory = Xlogin::FirmwareFactory.instance
      session = factory.build_from_hostname(hostname, args)

      if block_given?
        begin yield session ensure session.close end
      else
        session
      end
    end

    def template_dir(*template_dirs)
      template_dirs.each do |template_dir|
        template(*Dir.glob(File.join(template_dir, '*.rb')))
      end
    end

    def configure(name)
      factory = Xlogin::FirmwareFactory.instance
      template = factory.get_template(name) || Xlogin::Firmware.new
      yield template if block_given?
      factory.set_template(name, template)
    end

    def alias(new_name, name)
      factory = Xlogin::FirmwareFactory.instance
      factory.alias_template(new_name, name)
    end

  end

end
