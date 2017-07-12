$:.unshift File.dirname(__FILE__)

require 'xlogin/firmware'
require 'xlogin/firmware_factory'
require 'xlogin/version'

module Xlogin

  class GeneralError < StandardError; end

  # default template directory
  TEMPLATE_DIR = File.join(File.dirname(__FILE__), 'xlogin', 'templates')

  class << self
    def factory
      @factory ||= configure_factory
    end

    def configure_factory(*template_dirs)
      unless @factory
        @factory = Xlogin::FirmwareFactory.instance

        template_dirs = [TEMPLATE_DIR, File.join(Dir.pwd, 'templates'), *template_dirs]
        template_dirs.compact.uniq.each do |dir|
          next unless FileTest.directory?(dir)
          @factory.load_template_file(*Dir.glob(File.join(dir, '*.rb')))
        end
      end
      @factory
    end

    def configure(name)
      template = factory.get_template(name) || Xlogin::Firmware.new
      yield template if block_given?

      factory.set_template(name, template)
    end

    def alias(new_name, name)
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
