require 'thread'

require 'starbot/transport'

require 'xmpp4r'
require 'xmpp4r/muc'
require 'xmpp4r/roster'

require 'starbot/ext/xmpp4r/message'
require 'starbot/encoding_patch.rb'

#Jabber::debug = true

class Starbot
  module Transport
    # A simple starbot transport for XMPP.
    # It supports one-on-one chats, multi-user chats and private messaging in chats.
    # @todo implement Transport#when_authorized
    class Xmpp
      include Transport

      attr_reader :roster

      # Create an Xmpp transport, connect to an XMPP server and setup callbacks
      # to direct all communications to a given Starbot.
      # @param [Starbot] bot
      # @param [String] default room represented as a jabber id
      # @param [Hash] opts
      # @option opts [String] :jid jabber account id
      # @option opts [String] :pass account password
      # @option opts [String] :host jabber server address
      # @option opts [Fixnum] :port jabber server port number
      def initialize(bot, defroom, opts = {})
        setup(bot, defroom, opts)
        # Array of room jids that this bot is in
        @rooms = {}
        @roomlock = Mutex.new
        # @todo raise an error if :jid and :pass are not provided
        connect(@opts[:jid], @opts[:pass], @opts[:host], @opts[:port])
        @me     = @bot.contact_list.create(opts[:jid], opts[:jid].split("@")[0])
        @myjid  = Jabber::JID.new(opts[:jid])
        @roster = Jabber::Roster::Helper.new(@client)
        watch_roster
        watch_for_subscribers
        # It seems like jabber sends us the roster on connect, so we probably
        # don't need to get it manually here
        #@roster.get_roster

        rejoin_rooms
        watch_msgs
      end # initialize(opts = {})
      
      # Connect to an XMPP server.
      # @param [String] jid jabber account id
      # @param [String] pass the account password
      # @param [String] host as an ip, or dns address
      # @param [Fixnum] port (5222)
      def connect(jid, pass, host, port = 5222)
        @client = Jabber::Client.new(Jabber::JID::new(jid))
        @client.connect(host, port)
        @client.auth(pass)
        @client.send(Jabber::Presence.new.set_type(:available))
        self
      end # connect
      
      # Send a message directly to a contact.
      def sayto_contact(contact, msg)
        @logger.debug("sayto_contact(#{contact.respond_to?(:id) ? contact.id : contact}, #{msg})")
        if contact.is_a?(String)
          Jabber::Message::new(contact, "#{msg}").tap do |m|
            m.type = :chat
            @client.send(m)
          end #  |m|
          return nil
        end # contact.is_a?(String)
        
        if contact.is_a?(::Starbot::Contact)
          if contact.room.nil?
            Jabber::Message::new(contact.id, "#{msg}").tap do |m|
              m.type = :chat
              @client.send(m)
            end #  |m|
          elsif @rooms[contact.room.id].is_a?(Jabber::MUC::SimpleMUCClient)
            @rooms[contact.room.id].say(msg, contact.alias) 
          else
            @logger.error("contact's room #{contact.room.inspect}, is not a muc")
          end # contact.room.nil?
          return nil
        end # contact.is_a?(::Starbot::Contact)
        
        @logger.error("can't say anything to a contact of type #{contact.class}")
        nil
      end # sayto_contact(contact, msg)
      
      # Send a message to a room.
      def sayto_room(room, msg)
        @logger.debug("sayto_room(#{room.inspect}, #{msg})")
        if @rooms[room.id].is_a?(Jabber::MUC::SimpleMUCClient)
          @rooms[room.id].say(msg)
        else
          @logger.error("room #{room.inspect} is not a muc")
          # create the room
          join_room(room)
          @rooms[room.id].say(msg)
        end
        nil
      end # sayto_room(room, msg)
      
      def start_room(name, uid, *uids)
        nid    = name.gsub(/\s|\//, "")
        room   = bot.room_list.create(nid, name, [], Time.new)
        
        join_room(room)
        invite_room(nid, uid, *uids)
        yield(nid, {:topic => name, :timestamp => room.timestamp, :members => room.users})
      end # start_room(name, uid, *uids)
      
      def invite_room(rid, user, *users, &blk)
        raise ArgumentError, "#{rid} is not a known room" unless @rooms[rid]
        @logger.debug("inviting #{user} to room #{rid}")
        @rooms[rid].invite(user => "please join")
        
        unless users.empty?
          @logger.debug("inviting #{users.join(", ")} to room #{rid}")
          @rooms[rid].invite(Hash[users.map{|u| [u, "please join"] }])
        end # uids.empty?
        
        yield if block_given?
      end # invite_room(rid, user, *users, &blk)
      
      
      # Join a Room
      # @param [Starbot::Room] room
      # @return [Starbot::Room]
      # @todo remember password for rooms that are protected
      # @see http://xmpp.org/extensions/xep-0045.html
      def join_room(room)
        raise ArgumentError, "Starbot::Room expected" unless [:id, :password, :users].all?{|atr| room.respond_to?(atr) }
        return if @rooms.include?(room.id)
        Jabber::MUC::SimpleMUCClient.new(@client).tap do |muc|
          watch_muc(room, muc)
          muc.join("#{room.id}/#{@myjid.node}", room.password)
          room.users.push(@me)
          roomlock.synchronize do
            remembered_rooms = @bot.recal('xmpp:rooms', [])
            @bot.remember('xmpp:rooms', remembered_rooms.push(room.id)) unless remembered_rooms.include?(room.id)
          end #  synchronize

          @rooms[room.id] = muc
        end #  |muc|
        room
      end # join_room(room)
      
      def leave_room(room_id)
        return unless @rooms.include?(room_id)
        @rooms[room_id].exit
        roomlock.synchronize do
          remembered_rooms = @bot.recal('xmpp:rooms', [])
          if remembered_rooms.include?(room.id)
            remembered_rooms.delete(room.id)
            @bot.remember('xmpp:rooms', remembered_rooms)
          end # remembered_rooms.include?(room.id)
        end #  synchronize
        @rooms.delete(room_id)
      end # leave_room(room_id)
      
      
      # Register a message callback that converts jabber messages into Starbot
      # messages then passes them to the Starbot for routing.
      def watch_msgs
        @client.add_message_callback do |m|
          if !m.body.nil?
            if m.invite?
              contact = @bot.contact_list.create(m.invite_from, "")
              room    = @bot.room_list.create(m.from, "", [contact], Time.new)
              @logger.debug("received an invite from #{contact} in room #{room.id}: #{m.body}")
              join_room(room)
            else  
              contact = @bot.contact_list.create(m.from, "")
              msg     = ::Starbot::Msg.new(m.body, contact, Time.new, nil)
              @bot.route(m.body, msg)
            end # m.invite?
          end # !m.body.nil?
        end # |m|
      end # watch_msgs
      
      def watch_roster
        @roster.add_query_callback do |riq|
          if riq.query.is_a?(Jabber::Roster::IqQueryRoster)
            id  = Time.new.nsec
            riq.query.each do |cntct|
              cid = Time.new.nsec
              @logger.debug("*** -- *** #{id}:#{cid} #{cntct} (#{cntct.class})")
              case cntct.subscription
              when :both
                @logger.debug("#{id}:#{cid} adding #{cntct.jid} (#{cntct.iname}) to bot's contact list")
                @bot.contact_list.create(cntct.jid, cntct.iname).tap{|c| c.status = :authorized }
              when :from
                @logger.debug("*** -- *** #{id}:#{cid} subscription is from")
                # do something more
              when :none
                @logger.debug("*** -- *** #{id}:#{cid} subscription is none")
                # do something more
              when :remove
                @logger.debug("*** -- *** #{id}:#{cid} subscription is remove")
                # do something more
              when :to
                @logger.debug("*** -- *** #{id}:#{cid} subscription is to")
                # do something more
              end # cntct.subscription

            end #  |cntct|
          end # riq.query.is_a?(Jabber::Roster::IqQueryRoster)
        end #  |riq|
      end # watch_roster
      

      
      
    private
      attr_reader :roomlock
      
      # Rejoin rooms that the bot remembers being in before it was restarted.
      # @todo remember passwords for rooms that are protected.
      def rejoin_rooms
        @bot.recal('xmpp:rooms', []).map{|rid| @bot.room_list.create(rid, "", [@me], Time.new) }.each { |room| join_room(room) }
      end # rejoin_rooms
      
      # Watch a multi-user chat for message and process them through
      # the bot's router.
      # @param [Jabber::MUC::SimpleMUCClient] muc
      def watch_muc(room, muc)
        name = room.id

        muc.on_message do |time,nick,text|
          unless nick == @myjid.node
            @logger.debug("muc #{name} #{time.inspect} from: #{nick}; text: #{text}")
            contact      = @bot.contact_list.create("#{room.id}/#{nick}", nick)
            contact.room = room
            msg          = ::Starbot::Msg.new(text, contact, (time.nil? ? Time.new : Time.at(time)), room)
            @bot.route(text, msg)
          end # nick == @nick
        end # |time,nick,text|
        
        muc.on_private_message do |time,nick,text|
          @logger.debug("muc #{name} #{time.inspect} from: #{nick}; text: #{text}; (private)")
          unless nick == @myjid.node
            contact      = @bot.contact_list.create("#{room.id}/#{nick}", nick)
            contact.room = room
            msg          = ::Starbot::Msg.new(text, contact, (time.nil? ? Time.new : Time.at(time)), nil)
            @bot.route(text, msg)
          end # nick == @nick
        end # |time,nick,text|

        muc.on_room_message do |time,text|
          @logger.debug("muc #{name} #{time.inspect}; text: #{text}")
        end # |time,nick,text|
        
        muc.on_join do |time, nick|
          @logger.debug("muc #{name}: #{time.inspect} - #{nick} joined")
          unless nick == @myjid.node
            contact      = @bot.contact_list.create("#{room.id}/#{nick}", nick)
            contact.room = room
            room.users.push(contact)
          end # nick == @myjid.node
        end #  |pres|

        muc.on_leave do |time, nick|
          @logger.debug("muc #{name}: #{time.inspect} - #{nick} left")
          contact      = @bot.contact_list.create("#{room.id}/#{nick}", nick)
          contact.room = room
          room.users.delete(contact)
        end #  |pres|
      end # watch_muc(muc)
      
      # Whenever someone adds the bot to his contact list, it gets here
      # @see http://www.rubyfleebie.com/xmpp4r-a-real-world-example/
      def watch_for_subscribers
        @roster.add_subscription_request_callback do |item,pres|
          # we accept everyone
          @logger.info("accepting subscription from #{pres.from}")
          @roster.accept_subscription(pres.from)

          # Now it's our turn to send a subscription request
          @logger.info("subscribint to #{pres.from}")
          x = Jabber::Presence.new.set_type(:subscribe).set_to(pres.from)
          @client.send(x)
          
          m      = Jabber::Message::new
          m.to   = pres.from
          m.body = "We're friends now"
          @client.send(m)
        end # |item, pres|
      end # start_subscription_callback
      
    end # class::Xmpp
  end # module::Transport
end # class::Starbot
