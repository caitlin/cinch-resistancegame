require 'cinch'
require 'yaml'
require 'amatch'

require File.expand_path(File.dirname(__FILE__)) + '/core/game.rb'
require File.expand_path(File.dirname(__FILE__)) + '/core/round.rb'
require File.expand_path(File.dirname(__FILE__)) + '/core/team.rb'
require File.expand_path(File.dirname(__FILE__)) + '/core/player.rb'

module Cinch
  module Plugins

    CHANGELOG_FILE = File.expand_path(File.dirname(__FILE__)) + "/changelog.yml"

    class ResistanceGame
      include Cinch::Plugin

      def initialize(*args)
        super
        @game = Game.new
 
        @changelog     = self.load_changelog

        @mods          = config[:mods]
        @channel_name  = config[:channel]
        @settings_file = config[:settings]
        @games_dir     = config[:games_dir]

        @idle_timer_length    = config[:allowed_idle]
        @invite_timer_length  = config[:invite_reset]

        @idle_timer   = self.start_idle_timer
      end


      match /join/i,             :method => :join
      match /leave/i,            :method => :leave
      match /start/i,            :method => :start_game
      match /team confirm$/i,    :method => :confirm_team
      match /confirm/i,          :method => :confirm_team
      match /team (.+)/i,        :method => :propose_team
      match /propose (.+)/i,     :method => :propose_team
      match /vote (.+)/i,        :method => :team_vote
      match /mission (.+)/i,     :method => :mission_vote
      match /trap (.+)/i,        :method => :trap
      match /excalibur (.+)/i,   :method => :excalibur_use
      match /xcal (.+)/i,        :method => :excalibur_use
      match /sheath/i,           :method => :excalibur_no
      match /stay/i,             :method => :excalibur_no
      match /assassinate (.+)/i, :method => :assassinate_player
      match /kill (.+)/i,        :method => :assassinate_player
      match /lady (.+)/i,        :method => :lady_check

      # helpers
      match /invite/i,               :method => :invite
      match /subscribe/i,            :method => :subscribe
      match /unsubscribe/i,          :method => :unsubscribe
      match /who$/i,                 :method => :list_players
      match /missions/i,             :method => :missions_overview
      match /mission(\d)/i,          :method => :mission_summary
      match /info/i,                 :method => :game_info
      match /status/i,               :method => :status
      match /whoami/i,               :method => :whoami
      match /lance/i,                :method => :lancelot_info

      match /help ?(.+)?/i,          :method => :help
      match /intro/i,                :method => :intro
      match /rules ?(.+)?/i,         :method => :rules
      match /settings$/i,            :method => :get_game_settings       
      match /settings (base|avalon) ?(.+)?/i, :method => :set_game_settings
      match /changelog$/i,           :method => :changelog_dir
      match /changelog (\d+)/i,      :method => :changelog
      match /about/i,                :method => :about
      match /tips (resistance|spies|spy)/i, :method => :tips
   
      # mod only commands
      match /reset/i,              :method => :reset_game
      match /replace (.+?) (.+)/i, :method => :replace_user
      match /kick (.+)/i,          :method => :kick_user
      match /room (.+)/i,          :method => :room_mode
      match /roles/i,              :method => :who_spies


      listen_to :join,          :method => :voice_if_in_game
      listen_to :leaving,       :method => :remove_if_not_started
      listen_to :op,            :method => :devoice_everyone_on_start


      #--------------------------------------------------------------------------------
      # Listeners & Timers
      #--------------------------------------------------------------------------------
      
      def voice_if_in_game(m)
        if @game.has_player?(m.user)
          Channel(@channel_name).voice(m.user)
        end
      end

      def remove_if_not_started(m, user)
        if @game.not_started?
          self.remove_user_from_game(user)
        end
      end

      def devoice_everyone_on_start(m, user)
        if user == bot
          self.devoice_channel
        end
      end

      def start_idle_timer
        Timer(300) do
          puts "checking..."
          @game.players.map{|p| p.user }.each do |user|
            puts " => #{user.nick}"
            user.refresh
            if user.idle > @idle_timer_length
              self.remove_user_from_game(user)
              user.send "You have been removed from the #{@channel_name} game due to inactivity."
            end
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Helpers
      #--------------------------------------------------------------------------------

      def help(m, page)
        if page.to_s.downcase == "mod" && self.is_mod?(m.user.nick)
          User(m.user).send "--- HELP PAGE MOD ---"
          User(m.user).send "!reset - completely resets the game to brand new"
          User(m.user).send "!replace nick1 nick1 - replaces a player in-game with a player out-of-game"
          User(m.user).send "!kick nick1 - removes a presumably unresponsive user from an unstarted game"
          User(m.user).send "!room silent|vocal - switches the channel from voice only users and back"
          User(m.user).send "!roles - tells you the loyalties of the players in the game"
        else 
          case page
          when "2"
            User(m.user).send "--- HELP PAGE 2/3 ---"
            User(m.user).send "!info - shows spy count and team sizes for the game"
            User(m.user).send "!who - returns a player list of who is playing, in team leader order"
            User(m.user).send "!status - shows current status of the game, which phase of the round the game is in"
            User(m.user).send "!missions - shows all previous mission results"
            User(m.user).send "!mission1, !mission2, ... - shows a mission summary, including team voting history"
            User(m.user).send "!whoami - returns your current loyalty role"
          when "3"
            User(m.user).send "--- HELP PAGE 3/3 ---"
            User(m.user).send "!rules (avalon|avroles|teamsizes) - provides rules for the game; when provided with an argument, provides specified rules"
            User(m.user).send "!tips resistance|spies - provides tips for playing either side of the game"
            User(m.user).send "!subscribe - subscribe your current nick to receive PMs when someone calls !invite"
            User(m.user).send "!unsubscribe - remove your nick from the invitation list"
            User(m.user).send "!invite - invites #boardgames and subscribers to join the game"
            User(m.user).send "!changelog (#) - shows changelog for the bot, when provided a number it showed details"
          else
            User(m.user).send "--- HELP PAGE 1/3 ---"
            User(m.user).send "!join - joins the game"
            User(m.user).send "!leave - leaves the game"
            User(m.user).send "!start - starts the game"
            User(m.user).send "!team user1 user2 user3 - proposes a team with the specified users on it"
            User(m.user).send "!confirm - puts the proposed team up for voting"
            User(m.user).send "!vote yes|no|cancel - vote for teams to make or not, yes or no. Cancel will clear your current vote"
            User(m.user).send "!mission pass|fail - vote for missions to pass or not, pass or fail"
            User(m.user).send "!help (#) - when provided a number, pulls up specified page"
          end
        end
      end

      def intro(m)
        User(m.user).send "Welcome to ResistanceBot. You can join a game if there's one getting started with the command \"!join\". For more commands, type \"!help\". If you don't know how to play, you can read a rules summary with \"!rules\". If already know how to play, great. But there's a few things you should know."
        User(m.user).send "** Please DO NOT private message with other players! This is against the spirit of the game."
        User(m.user).send "** When you vote for teams and missions (!vote and !mission), MAKE SURE you are PMing with ResistanceBot. You could accidentally reveal your loyalty and ruin the game otherwise."
      end

      def rules(m, section)
        case section.to_s.downcase
        when "avalon"
          User(m.user).send "The Resistance: Avalon is the same basic game as The Resistance, with slightly different terms to fit the theme. However, there are some special roles that some players may have.  By and large, the game is played the same way. However, the special characters change the amount of information that players start the game with."
          User(m.user).send "All Avalon games include Merlin and The Assassin. Other roles are optional (but have some dependencies)"
          User(m.user).send "Merlin is a member of the Resistance. His Wizardly abilities allow him to know who the Spies are.  While the Spies know who the Resistance are, they do not know which is Merlin. He can try to pass on information about the Spies, but he must be careful, lest the Spies identify him."
          User(m.user).send "The Assassin is a Spy. At the end of the game, if the Resistance have three successful Missions, then this is the Spies' last chance. The Assassin discusses with the other Spies who they think is Merlin. Once the Assassin has received guidance, he chooses a Resistance member to assassinate. If their victim really is Merlin, the Spies win. Otherwise, the Resistance win."
          User(m.user).send "For information about the optional roles, see !rules avroles"
        when "avroles"
          User(m.user).send "Percival is a member of the Resistance. He learns who Merlin is. He can use what Merlin says, and how he votes to garner information about the Spies. His principle aim, however, is to draw the attention of the Assassin away from Merlin. If the Resistance succeed in 3 Missions, if Percival has done his job right, the Assassin will fail to kill Merlin. However, watch out if Morgana is in the game."
          User(m.user).send "Mordred is a Spy. The other Spies know he is a Spy but do not know that he is Mordred. Merlin is unable to identify him, which means he doesn't have full information on all the Spies. (Merlin will see one fewer spies than are in the game)"
          User(m.user).send "Oberon is a Spy. However, he doesn't know who his fellow Spies are, and they do not know him, either.  (The other Spies will see one fewer Spies than are in the game). Merlin can identify Oberon as a Spy."
          User(m.user).send "Morgana is a Spy. Percival must be in the game to use Morgana. The other Spies know her as a Spy, as does Merlin, but none of them know her identity as Morgana.  However, Morgana's magic allows her to appear to Percival as if she were Merlin.  Percival will see two people claiming to be Merlin. He will know one is Resistance, the other a Spy. But he will not know for sure whose votes and conversation to trust."
          User(m.user).send "Lady of the Lake is a token given to a player that allows them to look at the loyalty of another player. Immediately after Quests 2, 3, and 4, the player with the Lady token will choose one player to examine. The player being examined then receives the Lady of the Lake token for the following round. A player that used Lady of the Lake token cannot have the Lady used on them."
        when "teamsizes"
          User(m.user).send "Team sizes are as follows:"
          User(m.user).send "5 players: 2, 3, 2, 3, 3"
          User(m.user).send "6 players: 2, 3, 4, 3, 4"
          User(m.user).send "7 players: 2, 3, 3, 4*, 4"
          User(m.user).send "8 players: 3, 4, 4, 5*, 5"
          User(m.user).send "9 players: 3, 4, 4, 5* ,5"
          User(m.user).send "10 players: 3, 4, 4, 5*, 5"
          User(m.user).send "When there are 7+ players, mission 4 requires TWO fails from the Spies." 
        else
          User(m.user).send "GAME SETUP: When the game starts, ResistanceBot will PM you to tell you whether you are a Resistance or a Spy. If you are a Spy, it will also tell you who the other Spies are.  The number of Spies is dependent on the total number of players, but will always be strictly less than the number of Resistance members."
          User(m.user).send "HOW TO WIN: There will be up to 5 Missions. If you are a member of the Resistance, you and the rest of the Resistance will win if 3 Missions Pass.  If you are a Spy, you and the other Spies will win if 3 Missions Fail. The game is over as soon as one of those conditions is met. There is another win condition for the Spies, explained below."
          User(m.user).send "HOW TO PLAY: The Team Leader for the round will Propose a Team to go on the Mission. The Team size changes from Mission to Mission, and Team sizes for the game are dependent on the number of players. Everyone then Votes whether they want to approve the Proposed Team to go on the Mission or not. Votes are made in secret, but how players Voted will be publicly revealed after all Votes are in. This is a majority Vote, and a tie means the Proposed Team will not go on the Mission."
          User(m.user).send "If the Team is not approved, the next player becomes the Team Leader and proposes a new Team. If the Team proposal process fails 5 times in a row, the Spies win the game immediately; in practice, as there are always fewer Spies than Resistance, this means that everyone should vote to approve the fifth proposed Team since the last Mission."
          User(m.user).send "When a proposed Team has been approved, they go on the Mission. The Team members then decide if they want the Mission to Pass or Fail. Resistance can only vote for the Mission to Pass; it is against their objective to do otherwise. Spies can choose to Pass OR Fail. Maybe they want to gain trust; but maybe they want to score a Mission Fail for their team."
          User(m.user).send "After Mission decisions have been made, the results are shuffled and revealed. It takes only ONE Fail for the whole Mission to Fail. (Exception: in games with 7 or more players, because of the increased number of Spies, it requires TWO Fails for 4th Mission to Fail.) A Mission which does not Fail will Pass. After a Mission has been completed (Pass or Fail), the next player becomes the new Team Leader and proposes the next Team."
        end
      end

      def about(m)
        User(m.user).send "ResistanceBot is an IRC-playable version of The Resistance by Don Eskridge. Find out more about the game on: http://boardgamegeek.com/boardgame/41114/the-resistance"
        User(m.user).send "This bot was created by: caitlinface. Many thanks to Chank (helping with development), timotab (helping with project management), and a large handful of #boardgames for testing early versions."
        User(m.user).send "It was written in Ruby, using the Cinch framework. Github: https://github.com/caitlin/cinch-resistancegame"
        #User(m.user).send "Copies \"sold\": 3"
      end

      def tips(m, for_who)
        case for_who
        when "resistance"
          User(m.user).send "--- TIPS FOR RESISTANCE ---"
          User(m.user).send "Get on the team - As a resistance operative you need to get on the mission teams, letting even a single spy on the team is enough to make it fail. The leader gets to propose team members, but everyone gets a vote. If the leader's proposal doesn't get enough votes then the next player becomes the leader and gets to propose a new team."
          User(m.user).send "Build trust in yourself - A good resistance player not only determines who the spies are, but also builds trust in themselves. The best way to build trust is to explain to others what you are attempting to do and why. When interrogated the spies can stumble in their web of deceit and expose themselves."
          User(m.user).send "Trust no one - If you don't trust everyone on the team then strongly consider rejecting the proposed Mission Team. Good resistance players will usually use three or more votes per round, carefully watching who is voting yes and asking them why. Remember the spies know each other and sometimes you can catch them approving a vote just because a spy was on the proposed team."
          User(m.user).send "Use all the information available - Information in The Resistance comes at multiple levels. First are players' voting patterns, second are Mission results, and third are cues that you can discern from player interactions. Resistance Operatives must use all the information at hand to root out the Spy infestation."
        when *["spies", "spy"]
          User(m.user).send "--- TIPS FOR SPIES ---"
          User(m.user).send "Act like the resistance - The resistance players are out to get you - think fast and remember if you act and vote like a resistance player you will be harder to spot. All the resistance operatives will want to go on the missions, and so should you."
          User(m.user).send "Change your MO - From game to game spies can get stuck in predictable patterns of behavior, such as never failing the first mission. If the resistance operatives can predict your behavior, they are more likely to uncover your identity."
          User(m.user).send "Never give up - Even if you are caught as a spy, you still have a valuable role to play in keeping the other spies safe. Use your status as a known spy to create confusion and discontent among the resistance operatives while protecting the remaining undercover spies."
        end
      end

      def list_players(m)
        if @game.players.empty?
          m.reply "No one has joined the game yet."
        else
          m.reply @game.players.map{ |p| p == @game.hammer ? "#{dehighlight_nick(p.user.nick)}*" : dehighlight_nick(p.user.nick) }.join(' ')
        end
      end

      def format_round_result(prev_round)
        result = prev_round.mission_success? ? 'PASSED' : 'FAILED'
        extra = []

        reverse_count = prev_round.mission_reverses

        # If the mission failed, or it's the 4th mission in a 7-10p game, show how many fails.
        # If the mission succeeded because of reverses, also show how many fails.
        if prev_round.special_round? || !prev_round.mission_success? || (prev_round.mission_success? && reverse_count > 0)
          fail_count = prev_round.mission_fails
          extra << (fail_count == 1 ? "#{fail_count} FAIL" : "#{fail_count} FAILS")
        end

        # If there are any reverses, show them too.
        extra << (reverse_count == 1 ? "#{reverse_count} REVERSE" : "#{reverse_count} REVERSES") if reverse_count > 0

        return result + (extra.empty? ? '' : " (#{extra.join(', ')})")
      end

      def missions_overview(m)
        round = @game.current_round.number
        (1..round).to_a.each do |number|
          prev_round = @game.get_prev_round(number)
          if ! prev_round.nil? && (prev_round.ended? || prev_round.in_mission_phase? || @game.current_round.in_assassinate_phase?)
            team = prev_round.team
            if prev_round.ended? || @game.current_round.in_assassinate_phase?
              mission_result = format_round_result(prev_round)
              if @game.variants.include?(:trapper)
                mission_result += " - #{prev_round.team_leader.user.nick} traps #{prev_round.trapped.user.nick}"
              end
              if @game.variants.include?(:excalibur)
                unless prev_round.excalibured.nil?
                  mission_result += " - #{prev_round.excalibur_holder.user.nick} xCals #{prev_round.excalibured.user.nick}"
                end
              end
            else
              mission_result = "AWAY ON MISSION"
            end
            m.reply "MISSION #{number} - Leader: #{dehighlight_nick(prev_round.team_leader.user.nick)} - Team: #{format_team(team, true)} - #{mission_result}"
          else
            #m.reply "A team hasn't been made for that round yet."
          end

        end
      end

      def mission_summary(m, round_number)
        number = round_number.to_i
        prev_round = @game.get_prev_round(number)
        if prev_round.nil?
          m.reply "That mission hasn't started yet."
        else
          teams = prev_round.teams
          m.reply "MISSION #{number}"
          teams.each_with_index do |team, i|
            went_team = team.team_makes? ? " - MISSION" : ""
            if team.team_votes.length == @game.players.length # this should probably be a method somewhere?
              m.reply "Team #{i+1} - Leader: #{dehighlight_nick(team.team_leader.user.nick)} - Team: #{format_team(team, true)} - Votes: #{self.format_votes(team.team_votes, true)}#{went_team}"
            elsif i == 0
              m.reply "No teams have been voted on yet."
            end
          end
          if prev_round.ended? || @game.current_round.in_assassinate_phase? || @game.current_round.in_lady_phase?
            trap_result = ""
            if @game.variants.include?(:trapper)
              trap_result = " - #{prev_round.team_leader.user.nick} traps #{prev_round.trapped.user.nick}"
            end

            xcal_result = ""
            if @game.variants.include?(:excalibur)
              if prev_round.excalibured.nil?
                xcal_result = " - Excalibur not used"
              else 
                xcal_result = " - Excalibur used on #{prev_round.excalibured.user.nick}"
              end
            end
            m.reply "RESULT: #{format_round_result(prev_round)}#{trap_result}#{xcal_result}"
          end
        end
      end

      def game_info(m)
        if @game.started?
          m.reply self.get_game_info
        end
      end

      def status(m)
        if @game.started?
          current_round = @game.current_round
          if current_round.in_team_making_phase?
            status = "Waiting on #{@game.team_leader.user} to propose a team of #{@game.current_team_size}"
          elsif current_round.in_team_proposed_phase?
            status = "Team proposed: #{self.current_proposed_team} - Waiting on #{@game.team_leader.user} to confirm or choose a new team"
          elsif current_round.in_vote_phase?
            status = "Waiting on players to vote: #{@game.not_voted.map(&:user).join(", ")}"
          elsif current_round.in_mission_phase?
            status = "Waiting on players to return from the mission: #{@game.not_back_from_mission.map(&:user).join(", ")}"
          elsif current_round.in_trapper_phase?
            status = "Waiting on #{@game.current_round.team_leader.user.nick} to choose a player to trap"
          elsif current_round.in_excalibur_phase?
            status = "Waiting on #{@game.current_round.excalibur_holder.user.nick} to choose to use Excalibur or not"
          elsif current_round.in_lady_phase?
            status = "Waiting on #{@game.lady_token.user.nick} to choose someone to examine with Lady of the Lake"
          elsif current_round.in_assassinate_phase?
            status = "Waiting on the assassin to choose a target"
          end
        else
          if @game.player_count.zero?
            status = "No game in progress."
          else
            status = "A game is forming. #{@game.player_count} players have joined: #{@game.players.map(&:user).join(", ")}"
          end
        end

        m.reply status
      end

      def changelog_dir(m)
        @changelog.first(5).each_with_index do |changelog, i|
          User(m.user).send "#{i+1} - #{changelog["date"]} - #{changelog["changes"].length} changes" 
        end
      end

      def changelog(m, page = 1)
        changelog_page = @changelog[page.to_i-1]
        User(m.user).send "Changes for #{changelog_page["date"]}:"
        changelog_page["changes"].each do |change|
          User(m.user).send "- #{change}"
        end
      end

      def invite(m)
        if @game.accepting_players?
          if @game.invitation_sent?
            m.reply "An invitation cannot be sent out again so soon."
          else      
            @game.mark_invitation_sent
            User(m.user).send "Invitation has been sent."

            settings = load_settings || {}
            subscribers = settings["subscribers"]
            current_players = @game.players.map{ |p| p.user.nick }
            subscribers.shuffle!.each do |subscriber|
              unless current_players.include? subscriber
                User(subscriber).refresh
                if User(subscriber).online?
                  User(subscriber).send "A game of Resistance is gathering in #playresistance ..."
                end
              end
            end

            # allow for reset after provided time
            Timer(@invite_timer_length, shots: 1) do
              @game.reset_invitation
            end
          end
        end
      end

      def subscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []
        if subscribers.include?(m.user.nick)
          User(m.user).send "You are already subscribed to the invitation list."
        else
          if User(m.user).authed?
            subscribers << m.user.nick 
            settings["subscribers"] = subscribers
            save_settings(settings)
            User(m.user).send "You've been subscribed to the invitation list."
          else
            User(m.user).send "Whoops. You need to be identified on freenode to be able to subscribe. Either identify (\"/msg Nickserv identify [password]\") if you are registered, or register your account (\"/msg Nickserv register [email] [password]\")"
            User(m.user).send "See http://freenode.net/faq.shtml#registering for help"
          end
        end
      end

      def unsubscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []
        if subscribers.include?(m.user.nick)
          if User(m.user).authed?
            subscribers.delete_if{ |sub| sub == m.user.nick }
            settings["subscribers"] = subscribers
            save_settings(settings)
            User(m.user).send "You've been unsubscribed to the invitation list."
          else
            User(m.user).send "Whoops. You need to be identified on freenode to be able to unsubscribe. Either identify (\"/msg Nickserv identify [password]\") if you are registered, or register your account (\"/msg Nickserv register [email] [password]\")"
            User(m.user).send "See http://freenode.net/faq.shtml#registering for help"
          end
        else
          User(m.user).send "You are not subscribed to the invitation list."
        end
      end


      #--------------------------------------------------------------------------------
      # Main IRC Interface Methods
      #--------------------------------------------------------------------------------

      def join(m)
        # self.reset_timer(m)
        if Channel(@channel_name).has_user?(m.user)
          if @game.accepting_players? 
            added = @game.add_player(m.user)
            unless added.nil?
              Channel(@channel_name).send "#{m.user.nick} has joined the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).voice(m.user)
            end
          else
            if @game.started?
              Channel(@channel_name).send "#{m.user.nick}: Game has already started."
            elsif @game.at_max_players?
              Channel(@channel_name).send "#{m.user.nick}: Game is at max players."
            else
              Channel(@channel_name).send "#{m.user.nick}: You cannot join."
            end
          end
        else
          User(m.user).send "You need to be in #{@channel_name} to join the game."
        end
      end

      def leave(m)
        if @game.accepting_players?
          left = @game.remove_player(m.user)
          unless left.nil?
            Channel(@channel_name).send "#{m.user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
            Channel(@channel_name).devoice(m.user)
          end
        else
          if @game.started?
            m.reply "Game is in progress.", true
          end
        end
      end

      def start_game(m)
        unless @game.started?
          if @game.at_min_players?
            if @game.has_player?(m.user)
              begin
                @game.start_game!
              rescue Game::TooManyRoles => e
                m.reply("There are too many #{e.type} roles. Please remove #{e.overflow} #{e.type} roles, or add more players.", true)
                return
              end

              @idle_timer.stop

              self.pass_out_loyalties

              Channel(@channel_name).send "The game has started. #{self.get_game_info}"

              if @game.avalon? 
                Channel(@channel_name).send "This is Resistance: Avalon, with #{self.game_settings[:roles].join(", ")}. Using variants: #{self.game_settings[:variants].join(", ")}"
              end
              if @game.with_variant?(:blind_spies)
                Channel(@channel_name).send "VARIANT: This is the Blind Spies variant. Spies do not reveal to each other."
              end
              if @game.with_variant?(:lancelot1)
                Channel(@channel_name).send "VARIANT: This is the Lancelot #1 variant. Lancelots will switch 0, 1, or 2 times, starting at the beginning of Mission 3. Evil Lancelot does not know other spies."
              end
              if @game.with_variant?(:lancelot2)
                Channel(@channel_name).send "VARIANT: This is the Lancelot #2 variant. Lancelots will switch 0, 1, or 2 times at times known in advance. The currently-evil Lancelot MUST fail missions he is on. Evil Lancelot does not know other spies."
                Channel(@channel_name).send "LANCELOT CHANGES SIDES: " + self.format_lancelot_deck
              end
              if @game.with_variant?(:lancelot3)
                Channel(@channel_name).send "VARIANT: This is the Lancelot #3 variant. Lancelots have revealed to each other."
              end
              if @game.player_count >= 7
                Channel(@channel_name).send "NOTE: This is a 7+ player game. Mission 4 will require TWO FAILS for the Spies."
              end

              Channel(@channel_name).send "Player order is: #{@game.players.map{ |p| p.user.nick }.join(' ')}"
              if @game.variants.include?(:lady)
                Channel(@channel_name).send "Lady of the Lake starts with #{@game.lady_token.user.nick}"
              end

              if @game.variants.include?(:lancelot2)
                @game.play_lancelot_card
                self.show_lancelot_card
              end

              Channel(@channel_name).send "MISSION #{@game.current_round.number}. Team Leader: #{@game.team_leader.user.nick}. Please choose a team of #{@game.current_team_size} to go on the first mission."
              User(@game.team_leader.user).send "You are team leader. Please choose a team of #{@game.current_team_size} to go on first mission. \"!team#{team_example(@game.current_team_size)}\""
              User(@game.team_leader.user).send "After you've chosen a team, \"!confirm\" to put it up for vote, or you can make a new team."
            else
              m.reply "You are not in the game.", true
            end
          else
            m.reply "Need at least #{Game::MIN_PLAYERS} to start a game.", true
          end
        end
      end

      def propose_team(m, team_members)
        if team_members != "confirm" 
          # make sure the providing user is team leader 
          player_nicks = @game.players.map{|p| p.user.nick }
          if m.user == @game.team_leader.user
            valid_team = false
            players = []
            players_with_xcal = []  
            player_names = []
            team_members.split(/[\s,]+/).each do |p| 
              fuzzy_matches = p.levenshtein_similar(player_nicks) # leve_matches
              # jaro_matches = p.jaro_similar(player_nicks)
              # fuzzy_matches = [jaro_matches,leve_matches].transpose.map {|x| x.reduce(:+)}
              high_fuzzy = fuzzy_matches.max
              puts "="*80
              puts player_nicks.inspect
              puts fuzzy_matches.inspect
              puts "="*80
              
              if high_fuzzy > 0.15
                best_nick = player_nicks[fuzzy_matches.index(high_fuzzy)]
              else 
                best_nick = p
              end
              player = @game.find_player(User(best_nick)) || best_nick
              xcal = p.end_with?("+") || p.start_with?("+")
              players_with_xcal << { :player => player, :xcal => xcal } 
              players << player
            end

            players.uniq!

            non_players = players.dup.delete_if{ |p| p.is_a? Player }
            actual_players = players.dup.keep_if{ |p| p.is_a? Player }

            # make sure the names are valid
            if non_players.count > 0
              User(@game.team_leader.user).send "Cannot find player(s): #{non_players.join(', ')}"
            # then check sizes
            elsif players.count < @game.current_team_size
              User(@game.team_leader.user).send "You don't have enough operatives on the team. You need #{@game.current_team_size}."
            elsif players.count > @game.current_team_size
              User(@game.team_leader.user).send "You have too many operatives on the team. You need #{@game.current_team_size}."
            # then we are okay
            else
              if @game.variants.include?(:excalibur)
                players_with_xcal.keep_if{ |px| px[:xcal] }
                # none
                if players_with_xcal.count == 0
                  User(@game.team_leader.user).send "You must give Excalibur to someone."
                # too many
                elsif players_with_xcal.count > 1
                  User(@game.team_leader.user).send "You can only give Excalibur to one operative."
                # should only be one by this point
                elsif players_with_xcal.first[:player].user == m.user
                  User(@game.team_leader.user).send "You cannot give Excalibur to yourself."
                else
                  valid_team = true
                  @game.current_round.team.give_excalibur_to(players_with_xcal.first[:player])
                end
              else
                valid_team = true
              end
            end
            if valid_team
              @game.make_team(actual_players)
              if @game.team_selected? # another safe check just because
                Channel(@channel_name).send "#{m.user.nick} is proposing the team: #{self.current_proposed_team}."
                @game.current_round.team_proposed
              end
            end
          else
            User(m.user).send "You are not the team leader."
          end
        end
      end

      def current_proposed_team
        format_team @game.current_round.team
      end

      def format_team(team, dehighlight = false)
        team.players.map do |p|
          if team.excalibur == p
            exc = "+" 
          end
          "#{exc}#{dehighlight ? dehighlight_nick(p.user.nick) : p.user.nick}"
        end.join(', ')
      end

      def confirm_team(m)
        # make sure the providing user is team leader 
        if m.user == @game.team_leader.user
          if @game.team_selected?
            unless @game.current_round.in_vote_phase?
              @game.current_round.call_for_votes
              Channel(@channel_name).send "The proposed team: #{self.current_proposed_team}. Time to vote!"
              @game.players.each do |p|
                hammer_warning = (@game.current_round.hammer_team?) ? " This is your LAST chance at voting a team for this mission; if this team is not accepted, the Resistance loses." : ""
                vote_prompt = "Time to vote! Vote whether or not you want #{@game.team_leader.user}'s team (#{self.current_proposed_team}) to go on the mission or not. \"!vote yes\" or \"!vote no\".#{hammer_warning}"
                User(p.user).send vote_prompt
              end
            else
              User(@game.team_leader.user).send "The team has already been confirmed"
            end
          else 
            User(@game.team_leader.user).send "You don't have enough members on the team. You need #{@game.current_team_size} operatives."
          end 
        else
          User(m.user).send "You are not the team leader."
        end
      end

      def team_vote(m, vote)
        if @game.current_round.in_vote_phase? && @game.has_player?(m.user)
          vote.downcase!
          if ['cancel'].include?(vote)
            @game.cancel_vote_for_team(m.user)
            User(m.user).send "Your vote has been canceled."
          elsif ['yes', 'no'].include?(vote)
            @game.vote_for_team(m.user, vote)
            User(m.user).send "You voted '#{vote}' for the team."
            if @game.all_team_votes_in?
              self.process_team_votes
            end
          else 
            User(player.user).send "You must vote 'yes' or 'no'."
          end
        end
      end

      def mission_vote(m, vote)
        if @game.current_round.in_mission_phase?
          player = @game.find_player(m.user)
          if @game.with_variant?(:lancelot2) && player.currently_evil_lancelot?
            valid_options = ['fail']
          elsif player.reverser?
            valid_options = ['pass', 'reverse']
          elsif player.spy?
            valid_options = ['pass', 'fail']
          else
            valid_options = ['pass']
          end

          if @game.current_round.team.players.include?(player)
            vote.downcase!
            if valid_options.include?(vote)
              unless  @game.compare_vote_for_mission(m.user, vote)
                @game.vote_for_mission(m.user, vote)
                User(m.user).send "You voted for the mission to '#{vote}'."
                if @game.all_mission_votes_in?
                  # It's not clear whether Trapper or Excalibur comes first?
                  # Arbitrarily picked Trapper.
                  if @game.variants.include?(:trapper)
                    self.prompt_for_trapper
                  elsif @game.variants.include?(:excalibur)
                    self.prompt_for_excalibur
                  else
                    self.process_mission_votes
                  end
                end
              end
            else 
              User(player.user).send "You must vote #{valid_options.join(" or ")}."
            end
          else
            User(player.user).send "You are not on this mission."
          end
        end
      end

      def assassinate_player(m, target)
        if @game.is_over? && @game.current_round.in_assassinate_phase?
          if @game.find_assassin.user == m.user
            killed = @game.find_player(target)

            # We don't let the Assassin kill a spy known to him.
            # An Oberon/Assassin can kill anyone.
            # A non-Oberon Assassin can kill any Resistance member, or Oberon.
            #
            # If Lancelots are in play and switch once:
            # Spies know NOT to kill original Evil Lance: he can't be Merlin.
            # They don't know who original Good Lance is, so he IS a target
            # for the kill.
            # Therefore, we to check a player's ORIGINAL allegiance.
            #
            # Finally, current code does not allow for Lancelot assassins,
            # so we avoid that hairy issue. Lancelot3/Assassin could work, but
            # is not implemented either for simplicity.

            assassin_is_oberon = @game.assassin_dual == :oberon
            if killed.nil?
              User(m.user).send "\"#{target}\" is an invalid target."
            elsif killed.original_spy? && !assassin_is_oberon && !killed.role?(:oberon)
              User(m.user).send "\"#{target}\" is not a member of the resistance"
            else
              spies, resistance = get_loyalty_info
              if killed.role?(:merlin)
                Channel(@channel_name).send "The assassin kills #{killed.user.nick}. The spies have killed Merlin! Spies win the game!"
              else 
                Channel(@channel_name).send "The assassin kills #{killed.user.nick}. The spies have NOT killed Merlin. Resistance wins!"
              end
              Channel(@channel_name).send "The spies were: #{spies.join(", ")}"
              Channel(@channel_name).send "The resistance were: #{resistance.join(", ")}."
              self.start_new_game
            end

          else
            User(m.user).send "You are not the assassin."
          end
        end
      end

      def lady_check(m, target)
        if @game.current_round.in_lady_phase?
          if @game.lady_token.user == m.user
            checking = @game.find_player(target)
            if checking.nil?
              User(m.user).send "\"#{target}\" is an invalid target."
            elsif checking.ladied?
              User(m.user).send "\"#{target}\" has already been checked."
            else
              Channel(@channel_name).send "#{m.user.nick} checks #{target} with the Lady of the Lake."
              if checking.spy?
                User(m.user).send "#{target} is EVIL"
              else 
                User(m.user).send "#{target} is GOOD"
              end
              @game.give_lady_to(checking)
              self.start_new_round
            end

          else
            User(m.user).send "You do not have the Lady of the Lake."
          end
        end
      end

      def trap(m, target)
        return unless @game.current_round.in_trapper_phase?
        unless @game.current_round.team_leader.user == m.user
          m.user.send('You are not the Trapper.')
          return
        end

        trapped = @game.find_player(target)
        if trapped.nil?
          m.user.send("\"#{target}\" is an invalid target.")
          return
        end

        old_vote = @game.current_round.use_trap_on(trapped)
        if old_vote.nil?
          m.user.send("#{target} was not on the mission.")
          return
        end

        Channel(@channel_name).send("#{m.user.nick} traps #{target}.")
        m.user.send("#{target} put in a #{old_vote.upcase}.")

        if @game.variants.include?(:excalibur)
          self.prompt_for_excalibur
        else
          self.process_mission_votes
        end
      end

      def excalibur_use(m, target)
        if @game.current_round.in_excalibur_phase?
          if @game.current_round.excalibur_holder.user == m.user
            excalibured = @game.find_player(target)
            if excalibured.nil?
              User(m.user).send "\"#{target}\" is an invalid target."
            elsif ! @game.current_round.team.has_player?(excalibured)
              User(m.user).send "#{target} was not on the mission."
            else
              Channel(@channel_name).send "#{m.user.nick} uses Excalibur on #{target}."
              old_vote = @game.current_round.mission_vote_for(excalibured)
              @game.current_round.use_excalibur_on(excalibured)
              new_vote = @game.current_round.mission_vote_for(excalibured)
              User(m.user).send "#{target} initially put in a #{old_vote.upcase}. You switched it to a #{new_vote.upcase}."
              self.process_mission_votes
            end
          else
            User(m.user).send "You do not hold Excalibur"
          end
        end
      end

      def excalibur_no(m)
        if @game.current_round.in_excalibur_phase?
          if @game.current_round.excalibur_holder.user == m.user
            Channel(@channel_name).send "#{m.user.nick} chooses not to use Excalibur."
            self.process_mission_votes
          else
            User(m.user).send "You do not hold Excalibur"
          end
        end
      end


      #--------------------------------------------------------------------------------
      # Game interaction methods
      #--------------------------------------------------------------------------------

      def team_example(size)
        size.times.map { |i| " name#{i+1}" }.join("")
      end
      
      def pass_out_loyalties
        @game.players.each do |p|
          User(p.user).send "="*40
          reply = self.tell_loyalty_to(p)
        end
      end

      def whoami(m)
        if @game.started?
          player = @game.find_player(m.user)
          reply = self.tell_loyalty_to(player)
          self.warn_about_lancelots(player) if @game.lancelots_switched?
        end
      end
      
      def tell_loyalty_to(player)
        spies = @game.avalon? ? @game.original_spies : @game.spies

        # If player is a spy, they can see other spies
        other_spies = player.spy? ? spies.reject { |s| s == player } : []
        # But not Spy Reverser if blind
        other_spies.reject! { |s| s.role?(:spy_reverser) } if @game.with_variant?(:blind_spy_reverser)

        if @game.avalon?
          # Spies don't see Oberon if he's in play.
          other_spies.reject! { |s| s.role?(:oberon) }

          if @game.variants.include?(:lancelot1) || @game.variants.include?(:lancelot2)
            evil_lancelot = @game.find_player_by_role(:evil_lancelot)
            show_evil_lance = "Evil Lancelot is: #{evil_lancelot.user.nick}."
          end

          # build info for the spies
          spy_info = ""

          unless other_spies.empty?
            other_spies = other_spies.map do |s| 
              s.role?(:evil_lancelot) ? "#{s.user.nick} (Evil Lancelot)" : s.user.nick
            end.join(', ')
            spy_info << " The other spies are: #{other_spies}."
          end
          # if playing with oberon, notify spies they are missing one spy in their info
          if oberon_note = @game.with_role?(:oberon) 
            spy_info << " Oberon is a spy, but does not reveal to you and does not know who the other spies are."
          end
          if @game.with_variant?(:blind_spy_reverser)
            spy_info << " The Spy Reverser is a spy, but does not reveal to you and does not know who the other spies are."
          end


          # here we goooo...
          if player.role?(:merlin)
            # sees spies minus mordred
            spies_minus_mordred = spies.reject{ |s| s.role?(:mordred) }.map{ |s| s.user.nick }
            missing = @game.with_role?(:mordred) ? " You don't see Mordred." : ""
            loyalty_msg = "You are MERLIN (resistance). Don't let the spies learn who you are. The spies are: #{spies_minus_mordred.join(', ')}.#{missing}"
          elsif player.role?(:assassin)
            loyalty_msg = "You are THE ASSASSIN (spy). Try to figure out who Merlin is.#{spy_info}"
          elsif player.role?(:percival)
            # sees merlin (and morgana)
            merlin = @game.find_player_by_role(:merlin)
            morgana = @game.find_player_by_role(:morgana)
            if morgana.nil?
              percy_info = "Merlin is: #{merlin.user.nick}."
            else
              revealed_to_percival_names = [merlin, morgana].shuffle.map{ |s| s.user.nick }
              percy_info = "Between #{revealed_to_percival_names.join(' and ')}, there is Merlin and Morgana."
            end
            loyalty_msg = "You are PERCIVAL (resistance). Help protect Merlin's identity. #{percy_info}"
          elsif player.role?(:good_lancelot)
            evil_lancelot = @game.find_player_by_role(:evil_lancelot)
            show_other = @game.variants.include?(:lancelot3) ? "Evil Lancelot is: #{evil_lancelot.user.nick}." : ""
            loyalty_msg = "You are GOOD LANCELOT (resistance).#{show_other}"
          elsif player.role?(:evil_lancelot)
            good_lancelot = @game.find_player_by_role(:good_lancelot)
            show_other = @game.variants.include?(:lancelot3) ? "Good Lancelot is: #{good_lancelot.user.nick}.#{spy_info}" : ""
            loyalty_msg = "You are EVIL LANCELOT (spy).#{show_other}"
          elsif player.role?(:mordred)
            loyalty_msg = "You are MORDRED (spy). You didn't reveal yourself to Merlin.#{spy_info}"
          elsif player.role?(:oberon)
            loyalty_msg = "You are OBERON (spy). You are a bad guy, but you don't reveal to them and they don't reveal to you."
          elsif player.role?(:morgana)
            loyalty_msg = "You are MORGANA (spy). You revealed yourself as Merlin to Percival.#{spy_info}"
          elsif player.role?(:spy_reverser)
            if @game.with_variant?(:blind_spy_reverser)
              loyalty_msg = 'You are THE SPY REVERSER. You do not know the other spies and they do not know you.'
            else
              loyalty_msg = "You are THE SPY REVERSER.#{spy_info}"
            end
          elsif player.role?(:spy)
            loyalty_msg = "You are A SPY.#{spy_info}"
          elsif player.role?(:resistance_reverser)
            loyalty_msg = "You are THE RESISTANCE REVERSER."
          elsif player.role?(:resistance)
            loyalty_msg = "You are a member of the RESISTANCE."
          else
            loyalty_msg = "I don't know what you are. Something's gone wrong."
          end

          if @game.assassin_dual && player.role?(@game.assassin_dual)
            loyalty_msg += "\nIn addition, you are THE ASSASSIN. Try to figure out who Merlin is."
          end
        else
          if player.role?(:spy)
            if @game.with_variant?(:blind_spies)
              spy_message = "This is the Blind Spies variant. You are a spy, but you don't reveal to the other spies and they don't reveal to you."
            else
              spy_message = other_spies.empty? ? '' : "The other spies are: #{other_spies.map { |s| s.user.name }.join(', ')}."
              if @game.with_variant?(:blind_spy_reverser)
                spy_message << "The Spy Reverser is a spy, but does not reveal to you and does not know who the other spies are."
              end
            end
            loyalty_msg = "You are A SPY! #{spy_message}"
          elsif player.role?(:spy_reverser)
            if @game.with_variant?(:blind_spy_reverser) || @game.with_variant?(:blind_spies)
              loyalty_msg = 'You are THE SPY REVERSER. You do not know the other spies and they do not know you.'
            else
              loyalty_msg = "You are THE SPY REVERSER. The other spies are: #{other_spies.map { |s| s.user.name }.join(', ')}"
            end
          elsif player.role?(:resistance_reverser)
            loyalty_msg = "You are THE RESISTANCE REVERSER."
          elsif player.role?(:resistance)
            loyalty_msg = "You are a member of the RESISTANCE."
          else
            loyalty_msg = "I don't know what you are. Something's gone wrong."
          end
        end
        User(player.user).send loyalty_msg
      end

      def warn_about_lancelots(player)
        message = nil
        if player.role?(:evil_lancelot)
          message = "You are now a member of the RESISTANCE."
        elsif player.role?(:good_lancelot)
          message = "You are now a SPY."
        elsif player.spy? && !player.role?(:oberon)
          evil_lancelot = @game.find_player_by_role(:evil_lancelot)
          message = "#{evil_lancelot.user.nick} (Evil Lancelot) is now Good. Good Lancelot has joined your side, but you do not know his identity."
        elsif player.role?(:merlin)
          message = "One of the spies you originally saw is now on the side of Good, and there is now an additional spy whose identity you do not know."
        end

        return if message.nil?
        User(player.user).send("WARNING: Lancelots have switched! " + message)
      end

      def get_game_info
        team_sizes = @game.team_sizes.values
        team_sizes.map! { |x| x + 1 } if @game.variants.include?(:trapper)
        if @game.player_count >= 7
          team_sizes[3] = team_sizes.at(3).to_s + "*"
        end
        "There are #{@game.player_count} players, with #{@game.spies.count} spies. Team sizes will be: #{team_sizes.join(", ")}"
      end

      def get_loyalty_info
        spies = @game.spies.sort_by{|s| s.loyalty}.map do |s|
          role = ""
          if s.loyalty != :spy
            role = s.loyalty.to_s.gsub("_", " ").titleize
            role += "/Assassin" if @game.assassin_dual == s.loyalty
            role = " (" + role + ")"
          end
          s.user.nick + role
        end
        resistance = @game.resistance.sort_by{|r| r.loyalty}.map do |r|
          "#{r.user.nick}" + (r.loyalty != :resistance ? " (#{r.loyalty.to_s.gsub("_"," ").titleize})" : "" )
        end
        return spies, resistance
      end

      def start_new_round
        @game.start_new_round
        self.show_lancelot_card

        two_fail_warning = (@game.current_round.special_round?) ? " This mission requires TWO FAILS for the spies." : ""
        Channel(@channel_name).send "MISSION #{@game.current_round.number}. Team Leader: #{@game.team_leader.user.nick}. Please choose a team of #{@game.current_team_size} to go on the mission.#{two_fail_warning}"
        User(@game.team_leader.user).send "You are team leader. Please choose a team of #{@game.current_team_size} to go on the mission. \"!team#{team_example(@game.current_team_size)}\""
      end

      def lancelot_info(m)
        return unless @game.started?
        msg = "Lancelots currently follow their " + (@game.lancelots_switched? ? "opposite" : "original") + " allegiance."
        if @game.with_variant?(:lancelot2)
          rounds_left = 5 - @game.current_round.number
          msg += " Lancelot changes sides in the upcoming rounds: " + format_lancelot_deck(rounds_left)
        end
        m.reply(msg)
      end

      def format_lancelot_deck(num = 5)
        # play_lancelot_card uses pop, which takes out the LAST element of an array.
        # To show the lancelot deck in the right order we must reverse!
        @game.lancelot_deck.reverse.take(num).map { |c|
          case c
          when :switch
            "YES"
          when :no_switch
            "NO"
          else
            "???"
          end
        }.join(", ")
      end

      def show_lancelot_card
        return if @game.current_round.lancelot_card.nil?

        if @game.current_round.lancelots_switch?
          Channel(@channel_name).send "LANCELOTS: Switch!"
          evil_lancelot = @game.find_player_by_role(:evil_lancelot)
          good_lancelot = @game.find_player_by_role(:good_lancelot)
          good_loyalty_msg = "LANCELOTS SWITCH: You are now a member of the RESISTANCE."
          evil_loyalty_msg = "LANCELOTS SWITCH: You are now a SPY."
          if @game.lancelots_switched?
            User(good_lancelot.user).send evil_loyalty_msg
            User(evil_lancelot.user).send good_loyalty_msg
          else
            User(good_lancelot.user).send good_loyalty_msg
            User(evil_lancelot.user).send evil_loyalty_msg
          end

        else
          Channel(@channel_name).send "LANCELOTS: No switch."
        end
      end

      def team_leader_prompt
        excalibur_instructions = @game.with_variant?(:excalibur) ? " You must give Excalibur to someone other than yourself; indicate your choice with a + symbol before or after that player's name." : ""
        prompt = "You are team leader. Please choose a team of #{@game.current_team_size} to go on the mission. \"!team#{team_example(@game.current_team_size)}\".#{excalibur_instructions}"
      end

      def process_team_votes
        # reveal the votes
        Channel(@channel_name).send "The votes are in for the team: #{format_team(@game.current_round.team)}"
        Channel(@channel_name).send self.format_votes(@game.current_round.team.team_votes, false)

        # determine if team makes
        if @game.current_round.team_makes?
          @game.go_on_mission
          Channel(@channel_name).send "This team is going on the mission!"
          @game.current_round.team.players.each do |p|
            if @game.with_variant?(:lancelot2) && p.currently_evil_lancelot?
              mission_prompt = 'Mission time! Since you are the currently-evil Lancelot, you can only choose to FAIL the mission. "!mission fail"'
            elsif p.reverser?
              mission_prompt = 'Mission time! Since you are a reverser, you have the option to PASS or REVERSE the mission. "!mission pass" or "!mission reverse"'
            elsif p.spy?
              mission_prompt = 'Mission time! Since you are a spy, you have the option to PASS or FAIL the mission. "!mission pass" or "!mission fail"'
            else
              mission_prompt = 'Mission time! Since you are resistance, you can only choose to PASS the mission. "!mission pass"'
            end
            User(p.user).send mission_prompt
          end
        else
          @game.try_making_team_again
          Channel(@channel_name).send "This team is NOT going on the mission. Reject count: #{@game.current_round.fail_count}"
          if @game.current_round.too_many_fails?
            self.do_end_game
          else
            hammer_warning = (@game.current_round.hammer_team?) ? " This is your LAST chance at making a team for this mission; if this team is not accepted, the Resistance loses." : ""
            Channel(@channel_name).send "MISSION #{@game.current_round.number}. #{@game.team_leader.user.nick} is the new team leader. Please choose a team of #{@game.current_team_size} to go on the mission.#{hammer_warning}"
            User(@game.team_leader.user).send "You are the new team leader. Please choose a team of #{@game.current_team_size} to go on the mission. \"!team#{team_example(@game.current_team_size)}\""
            @game.current_round.back_to_team_making
          end

        end
      end

      def format_votes(team_votes, dehighlight)
        yes_votes = team_votes.select{ |p, v| v == 'yes' }.map {|p, v| (dehighlight) ? dehighlight_nick(p.user.nick) : p.user.nick}.shuffle
        no_votes  = team_votes.select{ |p, v| v == 'no'  }.map {|p, v| (dehighlight) ? dehighlight_nick(p.user.nick) : p.user.nick}.shuffle
        if no_votes.empty?
          votes = "YES - #{yes_votes.join(", ")}"
        elsif yes_votes.empty?
          votes = "NO - #{no_votes.join(", ")}"
        else
          votes = "YES - #{yes_votes.join(", ")} | NO - #{no_votes.join(", ")}"
        end

        votes
      end

      def process_mission_votes
        # Since we pause while revealing results, we enter a "lock decisions" phase
        # so that players do not send extra commands and break the game.
        @game.current_round.lock_decisions

        # reveal the results
        Channel(@channel_name).send "The team is back from the mission..."

        # Show the results in the order: PASS, FAIL, REVERSE
        # REVERSE is longer, so sorting by length first moves it to the back.
        # P comes later in the alphabet than F, so we'll take the negative value so PASS comes first.
        votes = @game.current_round.mission_votes.values.sort_by! { |x| [x.length, -x[0].ord] }

        votes.each do |vote|
          sleep 3
          Channel(@channel_name).send vote.upcase
        end
        sleep 2
        # determine if mission passes
        if @game.current_round.mission_success?
          Channel(@channel_name).send "... the mission passes!"
        else
          Channel(@channel_name).send "... the mission fails!"
        end
        self.check_game_state
      end

      def prompt_for_trapper
        @game.current_round.ask_for_trapper
        leader = @game.current_round.team_leader
        Channel(@channel_name).send "TRAPPER: #{leader.user.nick}, select a player to trap."
        leader.user.send('Select a player to trap with "!trap name"')
      end

      def prompt_for_excalibur
        @game.current_round.ask_for_excalibur
        excalibur_holder = @game.current_round.excalibur_holder
        Channel(@channel_name).send "EXCALIBUR: #{excalibur_holder.user.nick}, do you want to use Excalibur?"
        User(excalibur_holder.user).send "You have Excalibur. You can use it on someone, \"!excalibur name\", or choose not to \"!sheath\""
      end

      def check_game_state
        Channel(@channel_name).send self.game_score
        if @game.is_over?
          self.do_end_game
        elsif @game.is_lady_round?
          @game.current_round.lady_time
          Channel(@channel_name).send "LADY OF THE LAKE. #{@game.lady_token.user.nick}, choose someone to check."
          User(@game.lady_token.user).send "You have Lady of the Lake. Please choose someone to check. \"!lady name\""
        else
          self.start_new_round
        end
      end

      def do_end_game
        spies, resistance = get_loyalty_info
        if @game.spies_win?
          Channel(@channel_name).send "Game is over! The spies have won!"
          Channel(@channel_name).send "The spies were: #{spies.join(", ")}"
          Channel(@channel_name).send "The resistance were: #{resistance.join(", ")}"
          self.start_new_game
        else
          if @game.avalon?
            @game.assassinate
            assassin = @game.find_assassin
            Channel(@channel_name).send "The resistance successfully completed the missions, but the spies still have a chance."
            Channel(@channel_name).send "The Assassin is: #{assassin.user.nick}. Choose a rebel to assassinate."
            User(assassin.user).send "You are the assassin, and it's time to assassinate one of the resistance. \"!assassinate name\""
          else
            Channel(@channel_name).send "Game is over! The resistance wins!"
            Channel(@channel_name).send "The spies were: #{spies.join(", ")}"
            Channel(@channel_name).send "The resistance were: #{resistance.join(", ")}"
            self.start_new_game
          end
        end
      end

      def start_new_game
        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).devoice(p.user)
        end
        @game.save_game(@games_dir)
        @game = Game.new
        @idle_timer.start
      end


      def game_score
        @game.mission_results.map{ |mr| mr ? "O" : "X" }.join(" ")
      end

      def devoice_channel
        Channel(@channel_name).voiced.each do |user|
          Channel(@channel_name).devoice(user)
        end
      end

      def remove_user_from_game(user)
        if @game.not_started?
          left = @game.remove_player(user)
          unless left.nil?
            Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
            Channel(@channel_name).devoice(user)
          end
        end
      end

      def dehighlight_nick(nickname)
        nickname.scan(/.{2}|.+/).join(8203.chr('UTF-8'))
      end

      #--------------------------------------------------------------------------------
      # Mod commands
      #--------------------------------------------------------------------------------

      def is_mod?(nick)
        # make sure that the nick is in the mod list and the user in authenticated 
        user = User(nick) 
        user.refresh
        user.authed? && @mods.include?(user.authname)
      end

      def reset_game(m)
        if self.is_mod? m.user.nick
          if @game.started?
            spies, resistance = get_loyalty_info
            Channel(@channel_name).send "The spies were: #{spies.join(", ")}"
            Channel(@channel_name).send "The resistance were: #{resistance.join(", ")}"
          end
          @game = Game.new
          self.devoice_channel
          Channel(@channel_name).send "The game has been reset."
          @idle_timer.start
        end
      end

      def kick_user(m, nick)
        if self.is_mod? m.user.nick
          if @game.not_started?
            user = User(nick)
            left = @game.remove_player(user)
            unless left.nil?
              Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).devoice(user)
            end
          else
            User(m.user).send "You can't kick someone while a game is in progress."
          end
        end
      end

      def replace_user(m, nick1, nick2)
        if self.is_mod? m.user.nick
          # find irc users based on nick
          user1 = User(nick1)
          user2 = User(nick2)
          
          # replace the users for the players
          player = @game.find_player(user1)
          player.user = user2

          # devoice/voice the players
          Channel(@channel_name).devoice(user1)
          Channel(@channel_name).voice(user2)

          # inform channel
          Channel(@channel_name).send "#{user1.nick} has been replaced with #{user2.nick}"

          # tell loyalty to new player
          User(player.user).send "="*40
          self.tell_loyalty_to(player)
        end
      end

      def room_mode(m, mode)
        if self.is_mod? m.user.nick
          case mode
          when "silent"
            Channel(@channel_name).moderated = true
          when "vocal"
            Channel(@channel_name).moderated = false
          end
        end
      end

      def who_spies(m)
        if self.is_mod? m.user.nick
          if @game.started?
            if @game.has_player?(m.user)
              User(m.user).send "You are in the game, goof!"
            else
              spies, resistance = get_loyalty_info  
              User(m.user).send "Spies are #{spies.join(", ")}."
              User(m.user).send "Resistance are #{resistance.join(", ")}."
            end
          else
            User(m.user).send "There is no game going on."
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Game Settings
      #--------------------------------------------------------------------------------

      def get_game_settings(m)
        with_variants = @game.variants.empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
        if @game.avalon?
          m.reply "Game settings: Avalon. Using roles: #{self.game_settings[:roles].join(", ")}.#{with_variants}"
        else
          m.reply "Game settings: Base.#{with_variants}"
        end
      end

      def set_game_settings(m, game_type, game_options = "")
        common_variant_options = ["lady", "excalibur", "trapper", "resistance_reverser", "spy_reverser", "blind_spy_reverser"]

        # this is really really wonky =(
        unless @game.started?
          game_change_prefix = m.channel.nil? ? "#{m.user.nick} has changed the game" : "The game has been changed"
          options = game_options || ""
          options = options.downcase.split(" ")
          if game_type.downcase == "avalon"
            valid_assassin_subs   = ["mordred", "oberon", "morgana"]
            valid_role_options    = ["percival"] + valid_assassin_subs
            valid_variant_options = ["lancelot1", "lancelot2", "lancelot3"] + common_variant_options

            assassin_dual = nil
            options.each_with_index { |opt, index|
              role = nil
              if opt.start_with?("+", "*")
                role = opt[1..-1]
              elsif opt.end_with?("+", "*")
                role = opt[0..-2]
              end

              if valid_assassin_subs.include?(role)
                assassin_dual = role
                options[index] = role
              end
            }

            role_options    = options.select{ |opt| valid_role_options.include?(opt) }
            variant_options = options.select{ |opt| valid_variant_options.include?(opt) }
            roles = ["merlin"] + role_options
            roles += ["assassin"] if assassin_dual.nil?
            if variant_options.include?("lancelot1") || variant_options.include?("lancelot2") || variant_options.include?("lancelot3")
              roles.push("good_lancelot").push("evil_lancelot")
            end

            roles.push("resistance_reverser") if variant_options.include?("resistance_reverser")
            roles.push("spy_reverser") if variant_options.include?("spy_reverser") || variant_options.include?("blind_spy_reverser")

            @game.change_type :avalon, :roles => roles, :variants => variant_options, :assassin_dual => assassin_dual
            game_type_message = "#{game_change_prefix} to Avalon. Using roles: #{self.game_settings[:roles].join(", ")}."
          else
            valid_variant_options = ["blind_spies"] + common_variant_options
            variant_options = options.select{ |opt| valid_variant_options.include?(opt.downcase) }

            roles = []
            roles.push("resistance_reverser") if variant_options.include?("resistance_reverser")
            roles.push("spy_reverser") if variant_options.include?("spy_reverser") || variant_options.include?("blind_spy_reverser")

            @game.change_type :base, :roles => roles, :variants => variant_options
            game_type_message = "#{game_change_prefix} to base."
          end
          with_variants = self.game_settings[:variants].empty? ? "" : " Using variants: #{self.game_settings[:variants].join(", ")}."
          Channel(@channel_name).send "#{game_type_message}#{with_variants}"
        end
      end

      def game_settings
        settings = {}
        settings[:roles] = @game.roles.map{ |r|
          dualed = @game.assassin_dual == r
          r.to_s.gsub("_", " ").titleize + (dualed ? "/Assassin" : "")
        }
        settings[:variants] = []
        if @game.avalon?
          settings[:variants] << "Lancelot #1" if @game.variants.include?(:lancelot1)
          settings[:variants] << "Lancelot #2" if @game.variants.include?(:lancelot2)
          settings[:variants] << "Lancelot #3" if @game.variants.include?(:lancelot3)
          settings[:variants] << "Lady of the Lake" if @game.variants.include?(:lady)
          settings[:variants] << "Excalibur" if @game.variants.include?(:excalibur)
          settings[:variants] << "Trapper" if @game.variants.include?(:trapper)
          settings[:variants] << "Blind Spy Reverser" if @game.variants.include?(:blind_spy_reverser)
        else
          settings[:variants] = @game.variants.map{ |o| o.to_s.gsub("_", " ").titleize }
        end
        settings
      end


      #--------------------------------------------------------------------------------
      # Settings
      #--------------------------------------------------------------------------------
      
      def save_settings(settings)
        output = File.new(@settings_file, 'w')
        output.puts YAML.dump(settings)
        output.close
      end

      def load_settings
        output = File.new(@settings_file, 'r')
        settings = YAML.load(output.read)
        output.close

        settings
      end

      def load_changelog
        output = File.new(CHANGELOG_FILE, 'r')
        changelog = YAML.load(output.read)
        output.close

        changelog
      end
      

    end
    
  end
end

#--------------------------------------------------------------------------------
# Other helpers
#--------------------------------------------------------------------------------

class String
  def titleize
    split(/(\W)/).map{ |w| ["of", "the"].include?(w) ? w : w.capitalize }.join
  end
end


