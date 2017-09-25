prompt(/#\z/)

login do |*args|
  username, password = *args
  waitfor(/Username: /) && puts(username)
  waitfor(/Password: /) && puts(password)
  waitfor
end
