Xlogin.configure :vyos do |os|
  os.prompt(/[$#] (?:\e\[K)?\z/n)

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/login:\s/)    && puts(username)
    waitfor(/Password:\s/) && puts(password)
    waitfor
  end

  os.bind(:config) do
    begin
      cmd('show configuration | no-more')
    ensure
      cmd('exit')
    end
  end

  os.bind(:save) do
    begin
      cmd('save')
    ensure
      cmd('exit')
    end
  end
end
