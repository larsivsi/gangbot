def fix_illegal(num, bool)
  if bool
    if num>=127 and num<=160
      return 734+(num-127)
    else
      return num
    end
  else
    if num>=734 and num<=767
      return 127+(num-734)
    else
      return num
    end
  end
end

def make_real(num)
  if num>=33 and num<=733
    return num
  elsif num < 33
    return make_real(733-(32-num))
  else
    return make_real(num-701)
  end
end

def encode(s)
  a = s.unpack('U'*s.length)
  ws = []
  retstring = ""

  dir = rand(2)
  num = fix_illegal(make_real(33+rand(400)),true)
  num2 = fix_illegal(make_real(33+rand(400)),true)

  for i in 0..a.length-1
    if a[i] == 32
      ws << [fix_illegal((i-ws.length+33),true)].pack('U').to_s
    else
      if dir == 0
        retstring << [fix_illegal(make_real(a[i]-num),true)].pack('U').to_s
      else
        retstring << [fix_illegal(make_real(a[i]+num),true)].pack('U').to_s
      end
    end
  end

  retstring << " "
  retstring << ws.to_s
  retstring << [fix_illegal(make_real((dir+num-num2)),true)].pack('U').to_s
  retstring << [num].pack('U').to_s
  retstring << [num2].pack('U').to_s

  return retstring
end

def decode(s)
  s = s.split(" ")
  a = s[0].unpack('U'*s[0].length)
  ws = s[1].unpack('U'*s[1].length)
  
  num2 = ws.pop
  num = ws.pop
  dir = make_real(fix_illegal(ws.pop,false)-num+num2)-701
  retstring = ""

  for i in 0..ws.length-1
    ws[i] = fix_illegal(ws[i],false)-33
  end

  for i in 0..a.length-1
    if ws.include?(i)
      retstring << " "
    end
    if dir == 0
      retstring << [make_real(fix_illegal(a[i],false)+num)].pack('U').to_s
    else
      retstring << [make_real(fix_illegal(a[i],false)-num)].pack('U').to_s
    end
  end

  return retstring
end

args = ARGV
if args.length != 2
  STDOUT.puts "too many/too few args"
elsif args[0] == '0'
  STDOUT.puts encode(args[1])
else
  STDOUT.puts decode(args[1])
end
