prompt(/[>#] \z/)

login do |*args|
  username, password = *args
  waitfor(/login:\s/)  && puts(username)
  waitfor(/Password:/) && puts(password)
  waitfor
end
