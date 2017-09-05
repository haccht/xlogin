$:.unshift File.dirname(__FILE__)

require 'xlogin/firmware'
require 'xlogin/firmware_factory'
require 'xlogin/version'

module Xlogin

  class GeneralError < StandardError; end

  BUILTIN_TEMPLATE_FILES = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))

  class << self
    def factory
      @factory ||= Xlogin::FirmwareFactory.instance
    end

    def source(source_file)
      factory.source(source_file)
    end

    def load_templates(*template_files)
      factory.load_template_files(*template_files)
    end

    def configure(name)
      factory  = Xlogin::FirmwareFactory.instance
      template = factory.get_template(name) || Xlogin::Firmware.new
      yield template if block_given?
      factory.set_template(name, template)
    end

    def alias(new_name, name)
      factory = Xlogin::FirmwareFactory.instance
      factory.alias_template(new_name, name)
    end

    def get(hostname, args = {})
      session = factory.build_from_hostname(hostname, args)

      if block_given?
        begin yield session ensure session.close end
      else
        session
      end
    end
  end

end
