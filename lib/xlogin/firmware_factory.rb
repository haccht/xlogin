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

      IO.readlines(db_file).each do |line|
        next if line =~ /^\s*#/

        nodename, nodetype, uri, optline = line.chomp.split(/\s+/)
        opts  = optline.to_s.split(',').map { |opt| opt.split('=') }
        value = { type: nodetype, uri: uri, opts: Hash[*opts.flatten] }
        @database[nodename] = value
      end
    end

    def find(nodename)
      @database[nodename]
    end

    def list
      @database.map{ |nodename, value| [nodename, value[:type]] }
    end

    def create(nodename, opts = {})
      item = nodename.kind_of?(Hash) ? nodename : find(nodename)
      raise Xlogin::GeneralError.new("Invalid target - #{nodename}") unless item && item[:type] && item[:uri]

      args = item[:opts].merge(opts).reduce({}) { |a, (k, v)| a.merge(k.to_s.downcase.to_sym => v) }
      firmware = send("build_#{item[:type]}")
      firmware.run(item[:uri], args)
    end

    def method_missing(name, *args, &block)
      if name.to_s =~ /^build_(\w+)$/
        firmware = Xlogin::FirmwareFactory[$1.to_s.downcase]
        raise Xlogin::GeneralError.new("'#{$1}' not found") unless firmware

        firmware
      else
        super(name, *args, &block)
      end
    end

  end
end
