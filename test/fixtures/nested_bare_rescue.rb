module Foo
  begin
    puts "hello"
  rescue
    begin
      puts "more"
    rescue
      puts "keeps going"
    end
  end
end
