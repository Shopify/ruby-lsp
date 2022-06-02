begin
  puts "begin"
rescue StandardError => e
  puts "stderror"
rescue Exception => e
  puts "exception"
ensure
  puts "ensure"
end
