require 'uri'
require 'stringio'
require 'xlogin/firmware'

module Xlogin
  class FirmwareFactory

    class << self
      def [](name)
        firmwares[name.to_s.downcase]
      end

      def register(name, firmware)
        firmwares[name.to_s.downcase] = firmware
      end

      def register_file(file)
        require file if file =~ /.rb$/
      end

      def register_dir(dir)
        Dir.entries(dir).each do |file|
          register_file(File.join(dir, file))
        end
      end

      private
      def firmwares
        @firmwares ||= Hash.new
      end
    end

    def initialize
      @database = Hash.new

      SourceDir.compact.each do |dir|
        source(File.join(dir, '.xloginrc'))
        source(File.join(dir, '_xloginrc'))
      end
    end

    def source(db_file)
      return unless File.exist?(db_file)

      content = IO.read(db_file)
      instance_eval(content)
    end

    def get(name)
      @database[name]
    end

    def set(type, name, uri, opts = {})
      @database[name] = opts.merge(uri: uri, type: type, name: name)
    end

    def list
      @database.values
    end

    def build(args)
      uri  = args.delete(:uri)
      type = args.delete(:type)
      name = args.delete(:name)
      opts = args.reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }
      raise Xlogin::GeneralError.new("Host not found: #{args}") unless uri && type

      firmware = Xlogin::FirmwareFactory[type].dup
      session  = firmware.run(uri, opts)
      session.name = name
      session
    end

    def build_from_hostname(hostname, **args)
      build(get(hostname).merge(args))
    end

    def method_missing(name, *args, &block)
      firmware = Xlogin::FirmwareFactory[name]
      super unless firmware && args.size >= 2

      set(name, *args)
    end

  end
end
