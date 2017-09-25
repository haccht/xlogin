prompt(/[$#] (?:\e\[K)?\z/n)

login do |*args|
  username, password = *args
  waitfor(/login:\s/)    && puts(username)
  waitfor(/Password:\s/) && puts(password)
  waitfor
end
