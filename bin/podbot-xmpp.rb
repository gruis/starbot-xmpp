#!/usr/bin/env ruby -wW1

require 'bundler/setup'
require 'starbot'
require 'starbot/transport/xmpp'

botname = 'simbot'
starbot  = Starbot.new(botname, :memoryfile => File.expand_path(File.dirname(__FILE__) + "/simbot.memories"))
xmpp    = Starbot::Transport::Xmpp.new(starbot, "caleb@icaleb.org", :log => starbot.log, :verbose => Logger::DEBUG,
                                      :jid => 'simbot@icaleb.org', :pass => 'l0ngsh0t89', :host => 'bs.icaleb.org')
me      = starbot.contact_list.create('simbot@icaleb.org', 'Simbot')


starbot.load_answers do
  answer(:default) {}
  answer('ping') { "pong" }

  answer('who am i?') { contact && contact.id }

  answer "what's your name?" do
    say("my name is, #{bot.name.inspect}")
  end #

  desc "ask starbot how long he has been up"
  answer "how old are you?" do
    u = uptime
    if u < 60
      "#{u} seconds old"
    elsif u < 3600
      "#{u / 60} minutes old"
    elsif u < 86400
      "#{u / 3600} hours old"
    else
      "#{uptime / 86400} days old"
    end # uptime < 86400
  end # 'how old are you?'

  answer 'ask for confirmation' do
    agree?('do you confirm?') do |conf, resp|
      conf ? sayto(resp.room, 'you confirmed') : sayto(resp.room, "you didn't confirm")
    end #  |conf|
  end # ask for confirmation

  answer 'ask me a question' do
    ask('What is the Ultimate Answer to the Ultimate Question of Life, The Universe, and Everything?') do |resp|
      resp.to_i == 42 ? sayto(resp.room || resp.contact, 'yup, correct') : sayto(resp.room || resp.contact, 'nope, not correct')
    end #  |ans, resp|
  end # ask me a question

  conversation "how's the weather?" do
    say "the weather's fine"
    temp  = 26
    ttemp = 24

    on(:no_answer) { end_conversation }
    on(:branch_end) { go_back }

    always_answer "how are you?" do
      say("I feel " + ['fine', 'depressed', 'happy', 'elated', 'hungry', 'bored', 'disgusted'].sample)
      ask("and how are you?") { |resp| say("glad to hear you are, '#{resp}'.")}
      answer 'quote' do
        say(helper(:quote))
      end
    end

    always_answer "ask me to agree" do
      agree?("do you agree") { |resp| say(resp ? "you agreed" : "you didn't agree") }
    end #

    answer "what's the temperature?" do
      say "it's #{temp}C"                              # answers and goes back a level
    end
    answer "what's the humidity?" do
      say "it's 78%"                                   # answers and goes back a level
    end
    answer "do I need an umbrella?" do
      say "nah, it's sunny now and won't rain today"   # answers and goes back a level
    end

    answer "what about tomorrow?" do
      say("what do you want to know about tomorrow?")
      answer "what will the temperature be?" do
        say "it'll be #{ttemp}C"                        # answers and goes back a level
      end
      answer "what will the humidity be?" do
        say "it'll be 100%"                             # answers and goes back a level
      end
      answer "will I need an umbrella?" do
        say "it's going to rain, so yeah, you do."      # answers and goes back a level
      end
    end
  end # "how's the weather?"

  answer 'what rooms are you in?' do
    say("Here's the rooms I'm in")
    rooms.each do |room|
      say("'#{room.id}' with #{room.users.map{|u| u.to_s}.join(", ")}")
    end #  |room|
    nil
  end #

  aka 'who are your friends?'
  aka 'tell me the names of your friends'
  answer 'who are you friends with?' do
    contacts.each do |contact|
      say("'#{contact.id}' - status : #{contact.status}")
    end #  |contact|
    nil
  end

  answer 'blow up' do
    say("tick")
    say("tick")
    say("tick")
    say("tick")
    say("tick")
    raise "Boom!"
  end #

  name "tell 'USER' MESSAGE"
  desc "tell simbot to send a message to a user"
  answer /^tell\s+(?!room )'([\.\w\s\-\@\/]+)' (.+)$/ do
    user_to_tell = params[0]
    msg_to_send  = params[1]

    cntct = contact(user_to_tell) || contact_list.create(user_to_tell, "")

    sayto(cntct, "#{cntct}, #{msg_to_send}")
    say("told #{cntct.id}, '#{msg_to_send}'")
  end # tell user

  answer /^create room (.*)$/ do
    create_room(params[0], raw.contact) do |r|
      sayto(r, "room '#{params[0]}' created by #{raw.contact}")
      say("room '#{params[0]}' created")
    end
  end #

  desc "describe the questions that podbot can answer"
  answer 'help' do
    bot.answers.map{ |name, desc| sprintf("%s  => %s", name, desc) }.join("\n")
  end

  answer /is podbot .+\?/ do
    ["i'm not telling", "that's my secret", "that's for me to know and you to find out", "keep it to yourself"].sample
  end

end # starbot.load_answers




#starbot.sayto(starbot.contact_list.create('caleb@icaleb.org', 'Caleb'), Starbot::Msg.new("hello it's #{Time.new}", me))

Thread.stop
