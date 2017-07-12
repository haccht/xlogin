Xlogin.configure :ios do |os|
  os.timeout(300)
  os.prompt(/[>$#]/)
  os.prompt(/yes \/ no: /) do
    puts opts[:force] ? 'y' : 'n'
  end

  os.bind(:login) do |password|
    waitfor(/Password: /) && puts(password)
    waitfor
  end

  os.bind(:enable) do |password|
    puts('enable')
    waitfor(/Password: /) && puts(password)
    waitfor
  end

  os.bind(:config) do
    begin
      cmd('terminal length 0')
      resp = cmd('show run')
      resp.lines[4..-2].join.to_s
    ensure
      cmd('exit')
    end
  end

  os.bind(:save) do
    begin
      cmd('write memory')
    ensure
      cmd('exit')
    end
  end
end
