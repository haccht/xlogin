Xlogin.configure :sros do |os|
  os.timeout(300)
  os.prompt(/[>$#] /)
  os.prompt(/y\/n:/) do
    puts opts[:force] ? 'y' : 'n'
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

  os.bind(:config) do
    begin
      cmd('environment no more')
      resp = cmd('admin display-config')
      resp.lines[2..-2].join.to_s
    ensure
      cmd('logout')
    end
  end
end
