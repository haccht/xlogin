Xlogin.configure :vyos do |os|
  os.prompt(/[$#] (?:\e\[K)?\z/n)

  os.bind(:login) do |*args|
    username, password = *args
    waitfor(/login:\s/)    && puts(username)
    waitfor(/Password:\s/) && puts(password)
    waitfor
  end
end
