def fixIllegal(num,bool)
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

def makeReal(num)
  if num>=33 and num<=733
    return num
  elsif num < 33
    return makeReal(733-(32-num))
  else
    return makeReal(num-701)
  end
end

def encode(s)
  a = s.unpack('U'*s.length)
  ws = []
  retstring = ""

  dir = rand(2)
  num = fixIllegal(makeReal(33+rand(400)),true)
  num2 = fixIllegal(makeReal(33+rand(400)),true)

  for i in 0..a.length-1
    if a[i] == 32
      ws << [fixIllegal((i-ws.length+33),true)].pack('U').to_s
    else
      if dir == 0
        retstring << [fixIllegal(makeReal(a[i]-num),true)].pack('U').to_s
      else
        retstring << [fixIllegal(makeReal(a[i]+num),true)].pack('U').to_s
      end
    end
  end

  retstring << " "
  retstring << ws.to_s
  retstring << [fixIllegal(makeReal((dir+num-num2)),true)].pack('U').to_s
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
  dir = makeReal(fixIllegal(ws.pop,false)-num+num2)-701
  retstring = ""

  for i in 0..ws.length-1
    ws[i] = fixIllegal(ws[i],false)-33
  end

  for i in 0..a.length-1
    if ws.include?(i)
      retstring << " "
    end
    if dir == 0
      retstring << [makeReal(fixIllegal(a[i],false)+num)].pack('U').to_s
    else
      retstring << [makeReal(fixIllegal(a[i],false)-num)].pack('U').to_s
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
