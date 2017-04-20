$:.unshift File.dirname(__FILE__)

module Xlogin

  require 'xlogin/firmware'
  require 'xlogin/firmware_factory'

  SourceDir = [
    File.join(File.dirname(__FILE__), 'xlogin'),
    ENV['HOME'],
    ENV['XLOGIN_HOME'],
    Dir.pwd
  ]

  class GeneralError < StandardError; end

  class << self
    def configure(name)
      firmware = Xlogin::FirmwareFactory[name] || Xlogin::Firmware.new
      yield firmware if block_given?

      Xlogin::FirmwareFactory.register(name, firmware)
    end

    def alias(new_name, original_name)
      firmware = Xlogin::FirmwareFactory[original_name]
      raise Xlogin::GeneralError.new("'#{original_name}' not found") unless firmware

      Xlogin::FirmwareFactory.register(new_name, firmware)
    end

    def get(nodename, opts = {})
      @factory ||= Xlogin::FirmwareFactory.new
      session = @factory.build(nodename, opts)

      if block_given?
        begin yield session ensure session.close end
      else
        session
      end
    end

  end

  Directory = File.join(File.dirname(__FILE__), 'xlogin', 'firmwares')
  Xlogin::FirmwareFactory.register_dir(Directory)

end
