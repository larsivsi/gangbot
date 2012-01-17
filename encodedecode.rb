# Move illegal chars (127-160) into reserved area (734-767)
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

# Make number fall within [33,733] (734-767 reserved for illegal characters).
def make_real(num)
  if num>=33 and num<=733
    return num
  elsif num < 33
    return make_real(733-(32-num))
  else
    return make_real(num-701)
  end
end

# Basically a caesar cipher
def encode_substitution_cipher(input)
  plaintext = input.unpack('U'*input.length)
  key = []
  output = ""

  # direction of caesar
  direction = rand(2)
  # number of caesar shifts
  num = fix_illegal(make_real(33+rand(400)),true)
  # obscurification number
  num2 = fix_illegal(make_real(33+rand(400)),true)

  for i in 0..plaintext.length-1
    # remove spaces
    if plaintext[i] == 32
      key << [fix_illegal((i-key.length+33),true)].pack('U').to_s
    else
      # forward caesar
      if direction
        output << [fix_illegal(make_real(plaintext[i]+num),true)].pack('U').to_s
      # backward caesar
      else
        output << [fix_illegal(make_real(plaintext[i]-num),true)].pack('U').to_s
      end
    end
  end

  output << " "
  output << key.to_s
  # obscurify direction
  output << [fix_illegal(make_real((direction+num-num2)),true)].pack('U').to_s
  output << [num].pack('U').to_s
  output << [num2].pack('U').to_s

  return output
end

def decode_substitution_cipher(input)
  input = input.split(" ")
  ciphertext = input[0].unpack('U'*input[0].length)
  key = input[1].unpack('U'*input[1].length)
  
  # obscurification number
  num2 = key.pop
  # caesar shift number
  num = key.pop
  # shift direction
  direction = make_real(fix_illegal(key.pop,false)-num+num2)-701
  output = ""

  for i in 0..key.length-1
    key[i] = fix_illegal(key[i],false)-33
  end

  for i in 0..ciphertext.length-1
    # add spaces
    if key.include?(i)
      output << " "
    end
    if direction
      output << [make_real(fix_illegal(ciphertext[i],false)-num)].pack('U').to_s
    else
      output << [make_real(fix_illegal(ciphertext[i],false)+num)].pack('U').to_s
    end
  end

  return output
end
