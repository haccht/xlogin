prompt(/[>$#]/)
prompt(/yes \/ no: /) do
  puts (Xlogin.authorized?)? 'y' : 'n'
end

login do |password|
  waitfor(/Password: /) && puts(password)
  waitfor
end

enable do |password, &block|
  puts('enable')
  waitfor(/Password: /) && puts(password)
  waitfor

  if block
    block.call
    cmd('disable')
  end
end
