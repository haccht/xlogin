timeout(300)
prompt(/[>$#]/)
prompt(/yes \/ no: /) do
  puts (Xlogin.authorized?)? 'y' : 'n'
end

bind(:login) do |password|
  waitfor(/Password: /) && puts(password)
  waitfor
end

bind(:enable) do |password|
  puts('enable')
  waitfor(/Password: /) && puts(password)
  waitfor
end
