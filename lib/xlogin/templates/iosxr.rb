Xlogin.configure :iosxr do |os|
  os.timeout(300)
  os.prompt(/#\z/)

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/Username: /) && puts(username)
    waitfor(/Password: /) && puts(password)
    waitfor
  end

  os.bind(:config) do
    begin
      cmd('terminal width 0')
      cmd('terminal length 0')
      resp = cmd('show run')
      resp.lines[3..-3].join.to_s
    ensure
      cmd('exit')
    end
  end
end
