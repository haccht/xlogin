Xlogin.configure :iosxr do |os|
  os.timeout(300)
  os.prompt(/#\z/)

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/Username: /) && puts(username)
    waitfor(/Password: /) && puts(password)
    waitfor
  end

  os.hook do |command|
    if command =~ /^(?:adm |admi |admin )?\s*(?:con|rel|red|cle|hw|ro)/
      # commands: configure, reload, redundancy, clear, hw-module, rollback
      #   with or without admin prefix is prihibited if not authorized.
      raise Xlogin::AuthorizationError.new("prohibited command: #{command}") unless Xlogin.authorized?
    end

    pass(command)
  end
end
