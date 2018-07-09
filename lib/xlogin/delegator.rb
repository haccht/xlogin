require 'uri'

module Xlogin
  class Template

    module RelayTemplate
      def build(uri, **params)
        target_host = params.delete(:relay)
        return super(uri, **params) unless target_host

        target_info = Xlogin.factory.get_info(target_host)
        target_temp = Xlogin.factory.get_template(target_info[:type])
        target_uri  = URI(target_info[:uri])

        login    = @methods.fetch(:login)
        delegate = @methods.fetch(:delegate)
        raise TemplateError.new("'login' and 'delegate' must be defined in the #{target_info[:type]} template.") unless login && delegate

        relay_uri = URI(uri.to_s)
        userinfo_cache = relay_uri.userinfo.dup
        relay_uri.userinfo = ''

        session = target_temp.build(relay_uri, **params)
        session.instance_exec(*userinfo_cache.split(':'), &login)
        session.instance_exec(target_uri, **params, &delegate)
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
    ## Write firmware template for 'relay_srv'
    #
    # login do |username, password|
    #   waitfor(/login:\s*\z/)    && puts(username)
    #   waitfor(/Password:\s*\z/) && puts(password)
    # end
    #
    # delegate do |uri, **opts|
    #   puts("telnet #{uri.host}")
    #   login(*uri.userinfo.split(':'))
    # end

  end
end
