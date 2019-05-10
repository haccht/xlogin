prompt(/[>$#]/)

login do |password|
  waitfor(/Password: /) && puts(password)
  waitfor
end

enable do |password|
  puts('enable')
  waitfor(/Password: /) && puts(password)
  waitfor
end
