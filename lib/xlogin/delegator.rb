require 'uri'

module Xlogin
  class Firmware

    module FirmwareDelegator
      def run(uri, opts = {})
        if hostname = opts.delete(:delegate)
          delegatee = FirmwareFactory.new.get(hostname)
          firmware  = FirmwareFactory[delegatee[:type]]

          firmware.on_exec do |args|
            if args['String'].strip =~ /^kill-session(?:\(([\s\w]+)\))?$/
              puts($1.to_s)
              close
            else
              instance_exec(args, &@on_exec) if @on_exec
              do_cmd(args)
            end
          end

          delegate = firmware.instance_eval { @methods[:delegate] }
          login1   = firmware.instance_eval { @methods[:login] }
          login2   = @methods[:login]

          bind(:login, &login1)

          session = super(delegatee[:uri], opts.merge(delegatee[:opts]))
          session.class.class_eval { define_method(:login, &login2) }
          session.instance_exec(URI(uri), &delegate)
          session
        else
          session = super(uri, opts)
        end
      end
    end

    prepend FirmwareDelegator

  end
end
