#!/usr/bin/ruby

# Use local config if it exists
if File::exists?('./gangbot.config.local.rb')
  require './gangbot.config.local'
else
  require './gangbot.config'
end
# Check for encode/decode
if File::exists?('./encodedecode.rb')
  require './encodedecode'
  ENCODEDECODE = true
else
  ENCODEDECODE = false
end
require 'socket'

# The irc class, which talks to the server and holds the main event loop
class IRC
  def initialize(server, port, nick, channel, admin, sister)
    @server = server
    @port = port
    @nick = nick
    @channel = channel
    @admin = admin
    @sister = sister
    @startTime = Time.new
    @notifies = []
    start_timer()
  end

  # Send a message to the irc server and print it to the screen
  def send(s)
    puts "--> #{s}"
    @irc.send "#{s}\n", 0 
  end

  # Connect to the IRC server
  def connect()
    @irc = TCPSocket.open(@server, @port)
    send "USER #{@nick} gangbot pt2 :#{@nick}"
    send "NICK #{@nick}"
    send "JOIN #{@channel}"
  end

  # Start a timer in a new thread. Used for !notify
  def start_timer()
    t1 = Thread.new do
      begin
        # To sync with clock
        sleep(60-Time.now.sec)
        while true
          start = Time.now
          for notify in @notifies
            if start >= notify[0]
              send "PRIVMSG #{notify[1]} :#{notify[2]}: you asked me to notify you now"
              @notifies.delete(notify)
            end
          end
          used = Time.now-start
          sleep(60-used)
        end
      rescue Exception => detail
        send "PRIVMSG #{@admin} :NOTIFY-THEAD:" + detail.message()
        for elem in detail.backtrace.split("\n")
          irc.send("PRIVMSG #{@admin} :" + elem)
        end
        retry
      end
    end
  end

 # Name says it all
 def uptime_in_secs()
    now_time = Time.new
    return (now_time.to_f - @startTime.to_f).to_i
  end

 # Secs are stupid
 def uptime_in_stf(uptime)
    days = hours = mins = 0
    if uptime >=  60 then
      mins = (uptime / 60).to_i 
      uptime = (uptime % 60 ).to_i
    end
    if mins >= 60 then
      hours = (mins / 60).to_i 
      mins = (mins % 60).to_i
    end
    if hours >= 24 then
      days = (hours / 24).to_i
      hours = (hours % 24).to_i
    end
    return "#{(days>0)?days.to_s+'d ':''}#{(hours>0)?hours.to_s+'h ':''}#{(mins>0)?mins.to_s+'m ':''}#{uptime}s"
  end

  # Extract nick and channel
  def analyze_input(s)
    if s =~ /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s(\S+)\s:([\s\S]*)$/i
      nick = $1
      channel = $4
      message = $5
    end
    return [nick,channel,message]
  end

  # Basically does everything
  def handle_server_input(s)
    s = s.strip
    puts s
    # Respond to serverping
    if s =~ /^PING :(.+)$/i
      puts "[ Server ping ]"
      send "PONG :#{$1}"
      return
    # Kicking
    elsif s =~ /^:(.+?)!(.+?)@(.+?)\sKICK\s(\S+)\s(\S+)\s:/i
      kicker = $1
      channel = $4
      save = $5
      if save == @sister
        send "MODE #{channel} -o #{kicker}"
        puts "DEOPed #{kicker}, REASON: KICKED #{save}"
      elsif save == @nick
        send "JOIN #{channel}"
        puts "Got kicked, rejoining #{channel}"
      end
      return
    # Sister joins
    elsif s =~ /^:(.+?)!(.+?)@(.+?)\sJOIN\s:(\S+)$/i
      nick = $1
      channel = $4
      if nick == @sister
        send "MODE #{channel} +o #{nick}"
        puts "OPed #{nick} for joining"
      end
      return
    # Standard messages
    else
      data = analyze_input(s)
      return_str = "PRIVMSG #{((data[1]==@nick)?data[0]:data[1])} "
    end

    # Message
    case data[2]
    # CTCP PING
    when /^[\001]PING (.+)[\001]$/i
      puts "[ CTCP PING from #{data[0]} ]"
      send "NOTICE #{data[0]} :\001PING #{data[1]}\001"
    # CTCP VERSION
    when /^[\001]VERSION[\001]$/i
      puts "[ CTCP VERSION from #{data[0]} ]"
      send "NOTICE #{data[0]} :\001VERSION yomi v1.0\001"
    # Decode message
    when /^!decode(.*)$/i
      message = $1.strip
      if ENCODEDECODE
        if message.length != 0
          decoded = decode_substitution_cipher(message)
          send "#{return_str}:#{decoded}"
        else
          send "#{return_str}:#{data[0]}, invalid input: check !help for guidence"
        end
      else
        send "#{return_str}:#{data[0]}: encode/decode module disabled"
      end
    # Encode message
    when /^!encode(.*)$/i
      message = $1.strip
      if ENCODEDECODE
        if message.length != 0
          encoded = encode_substitution_cipher(message)
          send "#{return_str}:#{encoded}"
        else
          send "#{return_str}:#{data[0]}, invalid input: check !help for guidence"
        end
      else
        send "#{return_str}:#{data[0]}: encode/decode module disabled"
      end
    # Add notificaion
    when /^!notify(.*)$/i
      message = $1.strip
      if message =~ /^\d+$/i
        if message.to_i < 10081
          now = Time.now
          noti = [Time.local(now.year,now.mon,now.day,now.hour,now.min)+(message.to_i*60),data[1],data[0]]
          if not @notifies.include?(noti)
            @notifies << noti
            send "#{return_str}:#{data[0]}: ok, i will hilight you in #{message.to_i} minutes (i only notify every full minute)"
          else
            send "#{return_str}:#{data[0]}: you already have a notify pending at that moment"
          end
        else
          send "#{return_str}:#{data[0]}: too large input"
        end
      elsif message =~ /^(\d\d):(\d\d)$/i
        hour = $1.to_i
        minute = $2.to_i
        if hour < 0 || hour > 23 || minute < 0 || minute > 59
          send "#{return_str}:#{data[0]}: #{message} is not a valid time"
        else
          now = Time.now
          if now.hour < hour || now.hour == hour && now.min < minute
            noti = [Time.local(now.year,now.mon,now.day,hour,minute),data[1],data[0]]
            if not @notifies.include?(noti)
              @notifies << noti
              send "#{return_str}:#{data[0]}: ok, i will hilight you at #{noti[0].strftime("%H:%M")} (i only notify every full minute)"
            else
              send "#{return_str}:#{data[0]}: you already have a notify pending at that moment"
            end
          else
            send "#{return_str}:#{data[0]}: we're already past that today..."
          end
        end
      end
    # Post uptime
    when /^!uptime/i
      uptime = uptime_in_secs()
      send "#{return_str}:I have been operational for #{uptime} seconds, aka #{uptime_in_stf(uptime)}"
    end
  end

  # Name says it all
  def main_loop()
    while true
      ready = select([@irc, $stdin], nil, nil, nil)
      next if not ready
      for s in ready[0]
        if s == $stdin then
          return if $stdin.eof
          s = $stdin.gets
          send s
        elsif s == @irc then
          return if @irc.eof
          s = @irc.gets
          handle_server_input(s)
        end
      end 
    end
  end
end

# Starts everything, reconnects at exception
irc = IRC.new(IRC_SECONDARY_SERVER, IRC_PORT, SECONDARY_BOT_NAME, IRC_CHANNEL, ADMIN, MAIN_BOT_NAME)
irc.connect()
begin
  irc.main_loop()
rescue Interrupt => detail
  puts detail.message()
  print detail.backtrace.join("\n")
rescue Exception => detail
  irc.send("PRIVMSG #{ADMIN} :Exception:" + detail.message())
  for elem in detail.backtrace
    irc.send("PRIVMSG #{ADMIN} :" + elem)
  end
  retry
end
