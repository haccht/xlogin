require 'uri'

module Xlogin
  class Template

    module RelayTemplate
      def build(uri, **params) 
        login_host = params.delete(:relay)
        return super(uri, **params) unless login_host

        login_info = Xlogin.factory.get(login_host)
        login_os   = Xlogin.factory.get_template(login_info[:type])
        login_uri  = URI(login_info[:uri])

        login    = @methods.fetch(:login)
        delegate = @methods.fetch(:delegate)

        relay_uri = URI(uri.to_s)
        userinfo_cache = relay_uri.userinfo.dup
        relay_uri.userinfo = ''

        session = login_os.build(relay_uri, **params)
        session.instance_exec(*userinfo_cache.split(':'), &login)
        session.instance_exec(login_uri, **params, &delegate)
        session
      end
    end

    prepend RelayTemplate


    ### Usage:
    ## Write xloginrc file
    #
    # vyos      'vyos01',        'telnet://user:pass@host:port'
    # relay_srv 'vyos01::relay', 'telnet://relay_user:relay_pass@relay_host:relay_port', relay: 'vyos01'
    #
    ## Write firmware definition
    #
    # require 'timeout'
    # login do |*args|
    #   username, password = *args
    #   waitfor(/login:\s*\z/)    && puts(username)
    #   waitfor(/Password:\s*\z/) && puts(password)
    # end
    #
    # delegate do |uri, opts|
    #   cmd("telnet #{uri.host}")
    #   login(*uri.userinfo.split(':'))
    # end

  end
end
