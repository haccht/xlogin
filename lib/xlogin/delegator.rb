require 'uri'

module Xlogin
  class Firmware

    module FirmwareDelegator
      def run(uri, opts = {})
        if hostname = opts.delete(:delegate)
          delegatee = FirmwareFactory.new.find(hostname)
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

          login_method = firmware.instance_eval { @methods[:login] }
          firmware.bind(:login,    &@methods[:login])
          firmware.bind(:delegate, &@methods[:delegate])

          session = firmware.run(uri, opts.merge(delegatee[:opts]))
          session.delegate(URI(delegatee[:uri]), &login_method)
          session
        else
          session = super(uri, opts)
        end
      end
    end

    prepend FirmwareDelegator

  end
end
