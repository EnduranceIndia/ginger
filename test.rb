def do_work
    puts "open handle"
    begin
         yield('data') if block_given?
    ensure
        puts "close handle"
    end
end

do_work {|sql|
     puts "Real work with #{sql}" 



     puts 'morereall wlrlk'
}

