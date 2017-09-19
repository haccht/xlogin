timeout(300)
prompt(/#\z/)

bind(:login) do |*args|
  username, password = *args
  waitfor(/Username: /) && puts(username)
  waitfor(/Password: /) && puts(password)
  waitfor
end

hook do |command|
  if command =~ /^(?:adm |admi |admin )?\s*(?:con|rel|red|cle|hw|ro)/
    # commands: configure, reload, redundancy, clear, hw-module, rollback
    #   with or without admin prefix is prihibited if not authorized.
    raise Xlogin::AuthorizationError.new("prohibited command: #{command}") unless Xlogin.authorized?
  end

  pass(command)
end
