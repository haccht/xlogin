Xlogin.configure :sros do |os|
  os.timeout(300)
  os.prompt(/[>$#] /)
  os.prompt(/y\/n:/) do
    puts (Xlogin.authorized?)? 'y' : 'n'
  end

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/Login:\s?/)    && puts(username)
    waitfor(/Password:\s?/) && puts(password)
    waitfor
  end

  os.bind(:enable_admin) do |password|
    puts('enable-admin')
    waitfor(/Password:\s?/) && puts(password)
    waitfor
  end
end
