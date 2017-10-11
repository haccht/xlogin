prompt(/[>$#] /)
prompt(/y\/n:/) do
  puts (Xlogin.authorized?)? 'y' : 'n'
end

bind(:login) do |*args|
  username, password = *args
  waitfor(/Login:\s?/)    && puts(username)
  waitfor(/Password:\s?/) && puts(password)
  waitfor
end

bind(:enable_admin) do |password|
  puts('enable-admin')
  waitfor(/Password:\s?/) && puts(password)
  waitfor
end
