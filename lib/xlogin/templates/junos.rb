Xlogin.configure :junos do |os|
  os.timeout(300)
  os.prompt(/[>#] \z/)

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/login:\s/)  && puts(username)
    waitfor(/Password:/) && puts(password)
    waitfor
  end

  os.bind(:config) do
    begin
      cmd('show configuration | no-more')
    ensure
      cmd('exit')
    end
  end
end
