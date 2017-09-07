Xlogin.configure :ios do |os|
  os.timeout(300)
  os.prompt(/[>$#]/)
  os.prompt(/yes \/ no: /) do
    puts (Xlogin.authorized?)? 'y' : 'n'
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
end
