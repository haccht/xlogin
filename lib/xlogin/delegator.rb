require 'uri'

module Xlogin
  class Firmware

    module FirmwareDelegator
      def run(uri, opts = {})
        if hostname = opts.delete(:delegate)
          delegatee = FirmwareFactory.new.get(hostname)
          delegatee_os  = FirmwareFactory[delegatee[:type]]
          delegatee_uri = URI(delegatee[:uri])
          delegatee_uri.userinfo = ''

          delegatee_os.on_exec do |args|
            if args['String'].strip =~ /^kill-session(?:\(([\s\w]+)\))?$/
              puts($1.to_s)
              close
            else
              instance_exec(args, &@on_exec) if @on_exec
              do_cmd(args)
            end
          end

          delegate = delegatee_os.instance_eval { @methods[:delegate] }
          login1   = delegatee_os.instance_eval { @methods[:login] }
          login2   = @methods[:login]

          session = super(delegatee_uri, opts.merge(delegatee[:opts]))
          session.instance_exec(*delegatee_uri.userinfo.split(':'), &login1)

          session.define_singleton_method(:login, &login2)
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
