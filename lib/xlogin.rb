$:.unshift File.dirname(__FILE__)

require 'xlogin/firmware'
require 'xlogin/firmware_factory'
require 'xlogin/version'

module Xlogin

  ## where firmware templates locate.
  TemplateDir = File.join(File.dirname(__FILE__), 'xlogin', 'firmware_templates')

  ## where instance parameter definitions locate.
  SourceDirs  = [
    ENV['HOME'],
    ENV['XLOGIN_HOME'],
    Dir.pwd
  ]

  class GeneralError < StandardError; end

  class << self
    def factory
      unless @factory
        @factory = Xlogin::FirmwareFactory.instance

        Dir.entries(TemplateDir).each do |file|
          @factory.load_template_file(File.join(TemplateDir, file))
        end

        SourceDirs.compact.uniq.each do |dir|
          @factory.source(File.join(dir, '.xloginrc'))
          @factory.source(File.join(dir, '_xloginrc'))
        end
      end

      @factory
    end

    def configure(name)
      template = factory.get_template(name) || Xlogin::Firmware.new
      yield template if block_given?

      factory.set_template(name, template)
    end

    def alias(new_name, original_name)
      template = factory.get_template(original_name)
      raise Xlogin::GeneralError.new("'#{original_name}' not found") unless template

      factory.set_template(new_name, template)
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

  # do not remove this line!
  # initialize Xlogin systems and load related modules beforehand.
  Xlogin.factory

end
