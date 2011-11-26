#!/usr/bin/ruby

# Use local config if it exists
if File::exists?('gangbot.config.local.rb')
	require 'gangbot.config.local'
else
	require 'gangbot.config'
end
require 'rubygems'
require 'socket'
require 'net/http'
require 'net/https'
require 'htmlentities' #gem
require 'rss'
require 'dbi' #gem
require 'rexml/document'

# The irc class, which talks to the server and holds the main event loop
class IRC
  def initialize(server, port, nick, channel, admin, server_provider, sister)
    @server = server
    @port = port
    @nick = nick
    @channel = channel
    @admin = admin
    @server_provider = server_provider
    @sister = sister
    @startTime = Time.new
    @old = {}
    @users = {}
    sync_with_db()
    # Just make a random user agent
    @user_agent = 'Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.9.2.12) Gecko/20101027 Firefox/3.6.12'
  end

  # Send a message to the irc server and print it to the screen
  def send(s)
    puts "--> #{s}"
    @irc.send "#{s}\n", 0 
  end

  # Connect to the IRC server
  def connect()
    @irc = TCPSocket.open(@server, @port)
    send "USER #{@nick} gangbot pt1 :#{@nick}"
    send "NICK #{@nick}"
    send "JOIN #{@channel}"
  end

  # Connect to log DB...
  def log_db_connect()
    return DBI.connect(LOG_DB, LOG_DB_USER, LOG_DB_PW)
  end

  # Add another link to the old DB
  def add_old_to_db(link, nick_id)
    dbh = log_db_connect()
    dbh.do("INSERT INTO links(nick_id, link, created_at, times_posted) VALUES (?,?,NOW(),1);",nick_id,link)
    dbh.disconnect if dbh
  end

  # Increment times posted
  def update_old_db_counter(link)
    dbh = log_db_connect()
    dbh.do("UPDATE links SET times_posted = times_posted+1 WHERE link = ?",link)
    dbh.disconnect if dbh
    @old[link][2] = @old[link][2]+1
  end

  # Check whether a link is old or not, add to DB if new
  def check_for_old(link, nick, channel)
    if @old[link] != nil
      update_old_db_counter(link)
      send "PRIVMSG #{((channel==@nick)?nick:channel)} :#{nick}: OOOOLD! Your link has been posted #{@old[link][2]} times, and was first posted by #{@old[link][0]} #{uptime_in_stf((Time.new-@old[link][1]).to_i)} ago"
      return true
    else
      time = Time.new
      @old[link] = [nick,time,1]
      add_old_to_db(link,@users[nick])
      return false
    end
    return false
  end

  # We want synchronization of ids, as well as a hash for old links
  def sync_with_db()
    dbh = log_db_connect()
    users_query = dbh.prepare("SELECT id, nick FROM nicks;")
    users_query.execute()
    while row = users_query.fetch() do
      @users[row[1]] = row[0]
    end
    old_query = dbh.prepare("SELECT nick, link, links.created_at, times_posted FROM links, nicks WHERE nick_id = nicks.id;")
    old_query.execute()
    while row = old_query.fetch() do
      @old[row[1]] = [row[0],Time.parse(row[2].to_s)-Time.new.gmt_offset, row[3]]
    end
    dbh.disconnect if dbh
    puts "DONE INITIALIZING"
  end

  # Rather specialized, don't bother
  def dinner_find_day_for_feed()
    day = Time.new.wday
    if day == 1
      return "ma=on"
    elsif day == 2
      return "ti=on"
    elsif day == 3
      return "on=on"
    elsif day == 4
      return "to=on"
    elsif day == 5
      return "fr=on"
    else
      return "-1"
    end
  end

  # Same as above
  def dinner(source)
    feed_attribute = dinner_find_day_for_feed()
    if feed_attribute.length == 5
      source << "&#{feed_attribute}"
    else
      return feed_attribute
    end

    content = ""
    open(source) do |s| content = s.read end
    rss = RSS::Parser.parse(content, false)

    dinner_array = []
    counter = 0
    while counter < rss.items.size
      if rss.items[counter].title == "Uke #{Time.new.strftime('%W').to_i}"
        dinner_array = rss.items[counter].description.gsub(%r{</?[^>]+?>}, '').split(%r{\s\s+})
      end
      counter += 1
    end

    dinner_array.delete_at(0)
    dinner_array.delete_at(0)
    return dinner_array
  end

  # Magic 8ball thingy
  def eightball(nick,channel,s)
    if s.count(":") > 0
      s = s.strip
      array = s.split(':')
      if array.length > 1
        answ = array[rand(array.length)]
        eightball_log(@users[nick],s,answ)
        return "#{nick}, the answer to your question is: #{answ}"
      end
    end
    return "#{nick}, your input (#{s}) was invalid, please write in the following manner: '!8ball <alt1>:<alt2>:...'"
  end

  # Of course we want to log everything
  def eightball_log(nick_id,s,answ)
    dbh = log_db_connect()
    dbh.do("INSERT INTO eightball_logs(nick_id,query,answer,created_at) VALUES (?,?,?,NOW());",nick_id,s,answ)
    dbh.disconnect if dbh
  end

  # Get some last/next episode data for your favourite series
  def get_ep_info(series)
    series = series.gsub(' ','%20');
    url = URI.parse("http://services.tvrage.com/tools/quickinfo.php?show\=#{series}")
    session = Net::HTTP.new(url.host, url.port)
    session.open_timeout = 4
    session.read_timeout = 4
    resp = nil
    begin
      resp = session.get("#{url.path}?#{url.query}")
    rescue Timeout::Error
      puts "RESCUED TIMEOUT"
      return ["Request timed out :("]
    end
    array = resp.body.split("\n")
    ret_array = []
    array.each { |line|
      la = line.split("@")
      if la[0] == "Show Name"
        ret_array << "Show: #{la[1]}"
      elsif la[0] == "Latest Episode"
        ret_array << "Latest Episode: #{la[1].gsub("^",", ")}"
      elsif la[0] == "Next Episode"
        ret_array << "Next Episode: #{la[1].gsub("^",", ")}"
      end
    }
    return ret_array
  end

  # Get some basic info for spotify links
  def get_spotify_info(url)
    xml_data = Net::HTTP.get_response(URI.parse(url)).body
    doc = REXML::Document.new(xml_data)
    return "#{doc.elements["/track/name"].text} - #{doc.elements["/track/artist/name/"].text} (#{doc.elements["/track/album/name"].text})"
  end

  # Get titles for links posted
  def get_title_for_html(url)
    session = Net::HTTP.new(url.host, url.port)
    session.use_ssl = true if url.port == 443
    session.open_timeout = 3
    session.read_timeout = 3
    resp = nil
    ret = 0
    # get header
    begin
      if url.path.empty?
        resp = session.request_head('/', {'User-Agent' => @user_agent, 'Host' => url.host})
      else
        path = url.path + (url.query == nil ? "" : "?#{url.query}")
        resp = session.request_head(path, {'User-Agent' => @user_agent, 'Host' => url.host})
      end
    rescue Timeout::Error
      puts "RESCUED TIMEOUT"
      if ret < 3
        ret += 1
        retry
      else
        return "Request timed out :("
      end
    end
    if resp.content_type =~ /text\/html/i
      page = nil
      ret = 0
      # get body
      begin
        if url.path.empty?
          page = session.get('/')
        else
          path = url.path + (url.query == nil ? "" : "?#{url.query}")
          page = session.get(path)
        end
      rescue Timeout::Error
        puts "RESCUED TIMEOUT"
        if ret < 3
          ret += 1
          retry
        else
          return "Request timed out :("
        end
      end
      if page.body =~ /<title>([^<]+)<\/title>/i
        title = $1.gsub(/\n/,'')
        title = title.strip
        title = title.gsub(/\s+/,' ')
        return HTMLEntities.new.decode(title)
      end
      # no title
      return nil
    end
    # not text/html
    return nil
  end

  # Check that the URL is valid. Don't really trust this library...
  def is_valid_url(adr)
    if (adr =~ URI::regexp).nil?
      return false
    end
    return true
  end

  # Query the Movie DB
  # name is of legacy-reasons
  def query_rampage(word)
    dbh = DBI.connect(MOVIE_DB, MOVIE_DB_USER, MOVIE_DB_PW)
    query = dbh.prepare("SELECT name, rating FROM Movie WHERE name LIKE '%#{word}%';")
    query.execute()
    str_array = []

    while row = query.fetch() do
      str_array << "Name: #{row[0]}"
      str_array << "Rating: #{row[1]}"
    end
    dbh.disconnect if dbh

    if str_array.length == 0
      str_array << "No entries in the database that contains #{word}"
    elsif str_array.length > 12
      str_array = ["Too many entries found for #{word}, please be more spesific"]
    end
    return str_array
  end

  # Get MOTD from the Movie DB
  # name is of legacy-reasons
  def query_rampage_motd()
    dbh = DBI.connect(MOVIE_DB, MOVIE_DB_USER, MOVIE_DB_PW)
    query = dbh.prepare("SELECT name, rating FROM MovieOfTheDay;")
    query.execute()
    str_array = []

    while row = query.fetch() do
      str_array << "Name: #{row[0]}"
      str_array << "Rating: #{row[1]}"
    end
    dbh.disconnect if dbh

    return str_array
  end

  # Get the most active users
  def top(num)
    dbh = log_db_connect()
    query = dbh.prepare("SELECT nick, count(*) AS count FROM logs LEFT JOIN nicks ON nicks.id = logs.nick_id GROUP BY nick ORDER BY count DESC LIMIT ?;")
    query.execute(num)
    userdata = []
    total = 0
    top = []
    while row = query.fetch() do
      userdata << [row[0],row[1]]
    end
    total_query = dbh.prepare("SELECT count(*) FROM logs;")
    total_query.execute()
    while row = total_query.fetch() do
      total = row[0]
    end
    dbh.disconnect if dbh
    for data in userdata
      top << "#{data[0]}: #{data[1]} (#{sprintf("%.1f",(data[1].to_f/total)*100)}%)"
    end
    return top
  end

  # Name says it all
  def uptime_in_secs()
    nowTime = Time.new
    return (nowTime.to_f - @startTime.to_f).to_i
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

  # Kinda specialized, don't bother
  def weather(source,date)
    content = ""
    open(source) do |s| content = s.read end
    rss = RSS::Parser.parse(content,false)

    counter = 0
    temp_result = []
    title = ""
    while counter < rss.items.size
      if rss.items[counter].title =~ /^(.+) #{date}. (.+)$/
        if title.empty?
          title = rss.items[counter].title[%r{(\S+)\s(\S+)\s(\S+)\s(\S+)}]
        end
        temp_result << rss.items[counter].description
      end
      counter += 1
    end

    if title.empty?
      title = "No weatherdata available (input too large)"
    end

    return [title] + temp_result
  end

  # Must... log... everything...
  def log_input(s)
    if s =~ /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s(\S+)\s:([\s\S]*)$/i
      nick = $1
      channel = $4
      message = $5
      words = message.strip.split(/\s+/).size
      dbh = log_db_connect()
      if @users[nick] == nil
        dbh.do("INSERT INTO nicks(nick,name,created_at,updated_at,words) VALUES (?,'',NOW(),NOW(),?);",nick,words)
        query = dbh.prepare("SELECT id FROM nicks WHERE nick=?;")
        query.execute(nick)
        while row = query.fetch() do
          @users[nick] = row[0]
        end
      else
        dbh.do("UPDATE nicks SET updated_at=NOW(), words=words+? WHERE nick=?",words,nick)
      end
      dbh.do("INSERT INTO logs(nick_id,text,created_at) VALUES (?,?,NOW());",@users[nick],message)
      dbh.disconnect if dbh
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
      data = log_input(s)
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
      send "NOTICE #{data[0]} :\001VERSION #{@nick} v3.0\001"
    # 8ball
    when /^!8ball(.*)$/i
      send "#{return_str}:#{eightball(data[0],data[1],$1)}"
    # Query movie DB
    when /^!amdb(.*)$/i
      query = $1.strip
      result = query_rampage(query)
      for i in (0..result.length-1)
        send "#{return_str}:#{result[i]}"
      end
     # Get todays dinnerdata
     when /^!dinner|!middag/i
      if (1..5).include?(Time.new.wday)
        hangaren = dinner("http://sit.no/rss.ap?thisId=36444&lang=0")
        real = dinner("http://sit.no/rss.ap?thisId=36447&lang=0")
        send "#{return_str}:Hangaren:"
        for i in (0..hangaren.length-2)
          if i%2 == 0
            send "#{return_str}:#{hangaren[i]} #{hangaren[i+1]}"
          end
        end
        send "#{return_str}:Realfag:"
        for i in (0..real.length-2)
          if i%2 == 0
            send "#{return_str}:#{real[i]} #{real[i+1]}"
          end
        end
      else
        send "#{return_str}:Helg, ingen middag idag"
      end
    # Get last/next episode info
    when /^!ep(.*)$/i
      info = get_ep_info($1.strip)
      for element in info
        send "#{return_str}:#{element}"
      end
    # Halp!
    when /^!help|!halp/i
      send "#{return_str}:#{HALP_LINK}"
    # Movie of the day
    when /^!motd/i
      result = query_rampage_motd()
      for i in (0..result.length-1)
        send "#{return_str}:#{result[i]}"
      end
    # Repeat message in upper case
    when /^!repeat(.*)$/i
      send "#{return_str}:#{data[0]} asked me to repeat: #{$1.strip.upcase}"
    # Kick on "old"
    when /^\s*([o0]+)([l1]+)([d]+)([\S\s]*)$/i
      weiter = $4
      if data[0] != @sister && (weiter =~ /^\W*$/i || weiter =~ /^\W+([\S\s]*)$/i)
        send "KICK #{((data[1]==@nick)?data[0]:data[1])} #{data[0]} :Du er old!"
        puts "KICKED #{data[0]}, REASON: OLD"
      end
    # Give op to special users
    when /^!op/i
      if data[0] == @admin || data[0] == @server_provider
        send "MODE #{data[1]} +o #{data[0]}"
      else
        send "#{return_str}:#{data[0]}, you are not my creator, nor serverprovider!"
      end
    # Check whether statement is true or false
    when /^!statement/i
      if rand() > 0.49
        send "#{return_str}:Statement is true."
      else
        send "#{return_str}:Statement is false."
      end
    # Post link to DB-stats
    when /^!stats/i
      send "#{return_str}:Visit #{STATS_LINK} for stats"
    # Get the most active user
    when /^!top$/i
      top = top(1)
      send "#{return_str}:The undisputed king/queen of #{@channel} is:"
      send "#{return_str}:#{top[0]}"
    # Get the 5 most active users
    when /^!top5$/i
      top5 = top(5)
      send "#{return_str}:The top 5 active members of #{@channel} are:"
      for pers in top5
        send "#{return_str}:#{pers}"
      end
    # Post the uptime
    when /^!uptime/i
      uptime = uptime_in_secs()
      send "#{return_str}:I have been operational for #{uptime} seconds, aka #{uptime_in_stf(uptime)}"
    # Get weather data
    when /^!weather(.*)$/i
      temp = $1.strip
      is_number = not temp.gsub(%r{\D+},"").empty?
      number = temp.gsub(%r{\D+},"").to_i
      time = Time.new
      if is_number and (1..8).include?(number) 
        date = (time + number*3600*24).day
        result = weather("http://www.yr.no/sted/Norge/S%C3%B8r-Tr%C3%B8ndelag/Trondheim/Trondheim/varsel.rss",date)
        for element in result
          send "#{return_str}:#{element}"
        end
      elsif is_number and number == 0 and time.hour < 18
        result = weather("http://www.yr.no/sted/Norge/S%C3%B8r-Tr%C3%B8ndelag/Trondheim/Trondheim/varsel.rss",time.day)
        for element in result
          send "#{return_str}:#{element}"
        end
      elsif is_number and number == 0
        send "#{return_str}:No weatherservice available after 18:00"
      else
        send "#{return_str}:Invalid (or too large, keep within [0,8]) input, please write '!weather <days from now as digit>'"
      end
    # Spotify link. We don't like spotify anymore
    when /spotify:([\S]+):([\S]+)/i
      mode = $1
      if mode == "track"
        arg = get_spotify_info("http://ws.spotify.com/lookup/1/?uri=spotify:#{mode}:#{$2}")
        send "#{return_str}:>> #{arg}"
      else
        send "#{return_str}:mode '#{mode}' not supported"
      end
      send "#{return_str}:Due to recent changes, spotify is deprecated. Check out Grooveshark instead"
    # Link(s)
    when /http:\/\/|https:\/\//i
      data[2].scan(/http:\/\/(\S*)/i).each{ |match|
        url_str = "http://#{match}"
        if is_valid_url(url_str)
          check_for_old(url_str, data[0], data[1])
          url = URI.parse(url_str)
          if (title = get_title_for_html(url)) != nil
            send "#{return_str}:>> #{title}"
          end
        end
      }
      data[2].scan(/https:\/\/(\S*)/i).each{ |match|
        url_str = "https://#{match}"
        if is_valid_url(url_str)
          check_for_old(url_str, data[0], data[1])
          url = URI.parse(url_str)
          if (title = get_title_for_html(url)) != nil
            send"#{return_str}:>> #{title}"
          end
        end
      }
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
irc = IRC.new(IRC_MAIN_SERVER, IRC_PORT, MAIN_BOT_NAME, IRC_CHANNEL, ADMIN, SERVER_PROVIDER, SECONDARY_BOT_NAME)
irc.connect()
begin
  irc.main_loop()
rescue Interrupt => detail
  puts detail.message()
  print detail.backtrace.join("\n")
rescue Exception => detail
  irc.send("PRIVMSG #{ADMIN} :" + detail.message())
  for elem in detail.backtrace
    irc.send("PRIVMSG #{ADMIN} :" + elem)
  end
  retry
end
