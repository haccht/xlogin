require 'uri'

module Xlogin
  class Firmware

    module FirmwareDelegator
      def run(uri, opts = {})
        uri = URI(uri.to_s)

        if hostname = opts.delete(:delegate)
          target = FirmwareFactory.new.get(hostname)
          target_os  = FirmwareFactory[target[:type]]
          target_uri = URI(target[:uri])

          target_os.on_exec do |args|
            if args['String'].strip =~ /^kill-session(?:\(([\s\w]+)\))?$/
              puts($1.to_s)
              close
            else
              instance_exec(args, &@on_exec) if @on_exec
              do_cmd(args)
            end
          end

          login    = @methods[:login]
          delegate = @methods[:delegate]

          userinfo = uri.userinfo.dup
          uri.userinfo = ''

          session = target_os.run(uri, opts)
          session.instance_exec(*userinfo.split(':'), &login)
          session.instance_exec(target_uri, opts, &delegate)
          session
        else
          session = super(uri, opts)
        end
      end
    end

    prepend FirmwareDelegator

    ### Usage:
    ## Write xloginrc file
    #
    # vyos       'vyos01',          'telnet://user:pass@host:port'
    # consolesrv 'vyos01::console', 'telnet://console_user:console_pass@console_host:console_port', delegate: 'vyos01'
    #
    ## Write firmware definition
    #
    # require 'timeout'
    # Xlogin.configure :consolesrv do |os|
    #   os.bind(:login) do |*args|
    #    username, password = *args
    #    waitfor(/login:\s*\z/)    && puts(username)
    #    waitfor(/Password:\s*\z/) && puts(password)
    #  end
    #
    #  os.bind(:delegate) do |uri, opts|
    #    begin
    #      waittime = 3
    #      Timeout.timeout(waittime) do
    #        login(*uri.userinfo.split(':'), opts)
    #      end
    #    rescue Timeout::Error
    #    end
    #  end
    #end

  end
end
