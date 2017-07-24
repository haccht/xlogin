$:.unshift File.dirname(__FILE__)

require 'xlogin/firmware'
require 'xlogin/firmware_factory'
require 'xlogin/version'

module Xlogin

  class GeneralError < StandardError; end

  BUILDIN_TEMPLATES = Dir.glob(File.join(File.dirname(__FILE__), 'xlogin', 'templates', '*.rb'))

  class << self
    def factory
      @factory ||= load_templates(*BUILDIN_TEMPLATES)
    end

    def load_templates(*template_files)
      @loaded_template_files ||= []
      Xlogin::FirmwareFactory.instance.tap do |factory|
        files = template_files - @loaded_template_files
        factory.load_template_file(*files)
        @loaded_template_files += files
      end
    end

    def source(*source_files)
      _factory = Xlogin::FirmwareFactory.instance
      _factory.source(*source_files)
    end

    def configure(name)
      _factory = Xlogin::FirmwareFactory.instance
      template = _factory.get_template(name) || Xlogin::Firmware.new
      yield template if block_given?
      _factory.set_template(name, template)
    end

    def alias(new_name, name)
      _factory = Xlogin::FirmwareFactory.instance
      _factory.alias_template(new_name, name)
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
