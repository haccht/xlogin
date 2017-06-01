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
      @database[name] = { name: name, type: type, uri: uri, opts: opts }
    end

    def list
      @database.map { |nodename, args| args.merge(name: nodename) }
    end

    def build(name, args = {})
      item     = item.kind_of?(Hash) ? name : @database[name]
      item_uri = item[:uri] if item
      firmware = Xlogin::FirmwareFactory[item[:type]] if item
      raise Xlogin::GeneralError.new("Hostname '#{name}' not found ") unless item && item_uri && firmware

      opts = item[:opts] || {}
      opts = opts.merge(args).reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }

      session = firmware.dup.run(item_uri, opts)
      session.name = item[:name]
      session
    end

    def method_missing(name, *args, &block)
      firmware = Xlogin::FirmwareFactory[name]
      super unless firmware && args.size >= 2

      set(name, *args)
    end

  end
end
