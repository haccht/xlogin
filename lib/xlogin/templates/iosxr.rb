prompt(/#\z/)

bind(:login) do |*args|
  username, password = *args
  waitfor(/Username: /) && puts(username)
  waitfor(/Password: /) && puts(password)
  waitfor
end

hook do |command|
  case command.strip
  when /^conf/, /^ro/
    raise Xlogin::AuthorizationError.new("prohibited command: #{command}") unless Xlogin.authorized?
  else
    pass(command)
  end
end
