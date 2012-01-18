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

# Decode substitution cipher
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

# Regular row transposition
def encode_row_transposition_cipher(input)
  plaintext = input.unpack('U'*input.length)
  output = ""

  # create 2d array

  columns = Math.sqrt(plaintext.length).ceil
  array = []
  columns.times { array << Array.new(columns) }

  # fill array
  for i in 0..plaintext.length-1
    array[(i/columns).to_i][i%columns] = plaintext[i]
  end

  use_break_char = 0
  break_char = 0

  # if we have to pad the array
  if plaintext.length != columns*columns
    use_break_char = 1

    # find break character that's not illegal
    begin
      break_char = 33+rand(710)
    end while plaintext.include?(break_char) or (127..160).include?(break_char)

    array[(plaintext.length/columns).to_i][plaintext.length%columns] = break_char

    # fill the rest of the array with garbage
    for i in plaintext.length+1..columns*columns-1
      begin
        rand_char = 33+rand(710)
      end while (127..160).include?(rand_char)
      array[(i/columns).to_i][i%columns] = rand_char
    end
  end

  # create the shuffle key
  shuffle = Array.new(columns) { |i| i }.shuffle

  for i in shuffle
    for j in 0..columns-1
      output << [array[j][i]].pack('U').to_s
    end
  end

  shuffle_obsc = 200 + rand(300)

  output << " "
  shuffle.each { |num|
    num += shuffle_obsc
    output << [num].pack('U').to_s
  }
  output << [columns + shuffle_obsc].pack('U').to_s
  if use_break_char
    output << [break_char].pack('U').to_s
  end
  output << [use_break_char + shuffle_obsc].pack('U').to_s
  output << [shuffle_obsc].pack('U').to_s

  return output
end

# Decode row transposition
def decode_row_transposition_cipher(input)
  split_index = input.rindex(" ")
  ciphertext = input[0..split_index-1].unpack('U'*split_index)
  key = input[split_index+1..input.length].unpack('U'*(input.length-split_index+1))
  output = ""

  # get key information
  shuffle_obsc = key.pop
  use_break_char = key.pop - shuffle_obsc
  break_char = 0
  if use_break_char
    break_char = key.pop
  end
  columns = key.pop - shuffle_obsc

  # get the shuffle array
  shuffle = []
  for num in key
    shuffle << num - shuffle_obsc
  end

  # make 2d array
  array = []
  columns.times { array << Array.new(columns) }

  for i in 0..columns-1
    for j in 0..columns-1
      array[j][shuffle[i]] = ciphertext[i*columns+j]
    end
  end

  for i in 0..columns*columns
    num = array[(i/columns).to_i][i%columns]
    if num == break_char
      break
    end
    output << [num].pack('U').to_s
  end

  return output
end

# Classic product cipher
def encode_classic_cipher(input)
  return encode_row_transposition_cipher(encode_substitution_cipher(input))
end

# Decode classic product cipher
def decode_classic_cipher(input)
  return decode_substitution_cipher(decode_row_transposition_cipher(input))
end
