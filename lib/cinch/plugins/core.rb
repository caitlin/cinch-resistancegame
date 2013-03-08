require 'json'

#================================================================================
# GAME
#================================================================================

$player_count = 0

class Game


  MIN_PLAYERS = 5
  MAX_PLAYERS = 10
  LOYALTIES = {
      5  => { :resistance => 3, :spies => 2 },
      6  => { :resistance => 4, :spies => 2 },
      7  => { :resistance => 4, :spies => 3 },
      8  => { :resistance => 5, :spies => 3 },
      9  => { :resistance => 6, :spies => 3 },
      10 => { :resistance => 6, :spies => 4 }
    }
  TEAM_SIZES = {
      5  => { 1 => 2, 2 => 3, 3 => 2, 4 => 3, 5 => 3},
      6  => { 1 => 2, 2 => 3, 3 => 4, 4 => 3, 5 => 4},
      7  => { 1 => 2, 2 => 3, 3 => 3, 4 => 4, 5 => 4},
      8  => { 1 => 3, 2 => 4, 3 => 4, 4 => 5, 5 => 5},
      9  => { 1 => 3, 2 => 4, 3 => 4, 4 => 5, 5 => 5},
      10 => { 1 => 3, 2 => 4, 3 => 4, 4 => 5, 5 => 5}
    }

  attr_accessor :started, :players, :rounds, :type, :roles, :variants, :lancelot_deck, :lady_token, :invitation_sent, :time_start, :time_end
  
  def initialize
    self.started         = false
    self.players         = []
    self.rounds          = []
    self.type            = :base
    self.roles           = []
    self.variants        = []
    self.invitation_sent = false
    self.time_start      = nil
    self.time_end        = nil
    self.lancelot_deck   = []
    self.lady_token      = nil
  end

  #----------------------------------------------
  # Game Status
  #----------------------------------------------

  def started?
    self.started == true
  end

  def not_started?
    self.started == false 
  end

  def accepting_players?
    self.not_started? && ! self.at_max_players?
  end


  #----------------------------------------------
  # Game Setup
  #----------------------------------------------

  def at_max_players?
    self.player_count == MAX_PLAYERS
  end

  def at_min_players?
    self.player_count >= MIN_PLAYERS
  end

  def add_player(user)
    added = nil
    unless self.has_player?(user)
      new_player = Player.new(user)
      self.players << new_player
      added = new_player
    end
    added
  end

  def has_player?(user)
    found = self.find_player(user)
    found.nil? ? false : true
  end

  def remove_player(user)
    removed = nil
    player = self.find_player(user)
    unless player.nil?
      self.players.delete(player)
      removed = player
    end
    removed
  end

  def change_type(type, options = {})
    self.type = type
    if type == :avalon
      self.roles   = options[:roles].map(&:to_sym)
      self.variants = options[:variants].map(&:to_sym)
    else
      self.roles    = []
      self.variants = options[:variants].map(&:to_sym)
    end

    # # debug help
    # puts "="*80
    # puts "roles => #{roles.inspect}"
    # puts "variants => #{variants.inspect}"
    # puts "="*80
    
  end

  def avalon?
    self.type == :avalon
  end

  def with_variant?(variant)
    self.variants.include?(variant)
  end

  def mark_invitation_sent
    self.invitation_sent = true
  end

  def reset_invitation
    self.invitation_sent = false
  end

  def invitation_sent?
    self.invitation_sent == true
  end

  #----------------------------------------------
  # Game 
  #----------------------------------------------

  def start_game!
    self.started = true
    self.time_start = Time.now
    self.assign_loyalties
    self.make_lancelot_deck if self.variants.include?(:lancelot1)
    @current_round = Round.new(1)
    self.rounds << @current_round
    self.players.shuffle!.rotate!(rand(MAX_PLAYERS)) # shuffle seats
    self.assign_team_leader
    self.give_lady_to(self.players.last) if self.variants.include?(:lady)
    $player_count = self.player_count
  end

  def save_game(directory)
    output = File.new("#{directory}/#{Time.now.to_s}", 'w')
    output.puts YAML.dump(self)
    output.close
  end

  def assign_loyalties
    # get appropriate number of each loyalty per player count
    loyalties = LOYALTIES[self.players.count]
    resistance_count = loyalties[:resistance]
    spy_count = loyalties[:spies]

    loyalty_deck = []

    # add roles - this could be done way better probably
    # avalon roles added automatically, if no roles, we are playing base
    unless self.roles.empty?
      loyalty_deck << :merlin
      loyalty_deck << :assassin
      resistance_count -= 1
      spy_count -= 1

      if self.variants.include?(:lancelot3) || self.variants.include?(:lancelot1)
        loyalty_deck << :good_lancelot
        resistance_count -= 1
      end 
      if self.variants.include?(:lancelot3) || self.variants.include?(:lancelot1)
        loyalty_deck << :evil_lancelot
        spy_count -= 1
      end 

      if self.roles.include?(:percival)
        loyalty_deck << :percival
        resistance_count -= 1
      end 

      if self.roles.include?(:mordred)
        loyalty_deck << :mordred
        spy_count -= 1
      end 

      if self.roles.include?(:morgana)
        loyalty_deck << :morgana
        spy_count -= 1
      end 

      if self.roles.include?(:oberon)
        loyalty_deck << :oberon
        spy_count -= 1
      end 

    end

    # build the rest of the loyalty deck and shuffle
    resistance_count.times { loyalty_deck << :resistance } 
    spy_count.times { loyalty_deck << :spy } 
    loyalty_deck.shuffle!

    # assign loyalties
    self.players.each_with_index do |player, i|
      player.receive_loyalty(loyalty_deck[i])
    end
  end

  # Avalon variants

  def make_lancelot_deck
    self.lancelot_deck << [:switch] * 2
    self.lancelot_deck << [:no_switch] * 3
    self.lancelot_deck.flatten!.shuffle!    
  end

  def lancelots_switched?
    self.lancelot_deck.count(:switch) % 2 == 1
  end

  def switch_lancelots
    good_lancelot = self.find_player_by_role(:good_lancelot)
    evil_lancelot = self.find_player_by_role(:evil_lancelot)
    good_lancelot.switch_allegiance
    evil_lancelot.switch_allegiance
  end

  def give_lady_to(player)
    self.lady_token = player
  end

  def is_lady_round?
    lady_round = false
    if self.variants.include?(:lady) && [2,3,4].include?(@current_round.number)
      lady_round = true
    end
    lady_round
  end

  # BUILDING TEAMS

  def assign_team_leader
    @current_round.team.assign_team_leader(self.players.rotate!.first)
  end

  def make_team(players)
    @current_round.team.clear_team
    players.each do |player|
      self.add_to_team(player)
    end
    @current_round.team
  end

  def add_to_team(player)
    if player && @current_round.team.size < current_team_size
      @current_round.team.add_to_team(player)
      added = player
    end
    added || nil
  end

  def team_selected?
    @current_round.team.size == current_team_size
  end

  def vote_for_team(player, vote)
    @current_round.team.add_vote(self.find_player(player), vote)
  end

  def cancel_vote_for_team(player)
    @current_round.team.remove_vote(self.find_player(player))
  end

  def not_voted
    all_players = self.players
    voted_players = @current_round.team.voted
    not_voted = all_players.reject{ |player| voted_players.include?(player) }
    not_voted
  end

  def all_team_votes_in?
    self.not_voted.size == 0
  end

  def try_making_team_again
    @current_round.make_new_team
    self.assign_team_leader
  end

  def hammer
    if self.started?
      self.players.at( 4 - @current_round.fail_count ) # 5 - fail count - 1 for index offset
    end
  end

  # MISSION

  def vote_for_mission(player, vote)
    @current_round.mission_votes[self.find_player(player)] = vote
  end

  def compare_vote_for_mission(player, vote)
    @current_round.mission_votes[self.find_player(player)] == vote
  end

  def not_back_from_mission
    team_players = @current_round.team.players
    back_players = @current_round.mission_votes.keys
    not_back = team_players.reject{ |player| back_players.include?(player) }
    not_back
  end

  def all_mission_votes_in?
    self.not_back_from_mission.size == 0
  end

  # NEXT ROUND

  def check_game_state
    if self.started?
      if @current_round.in_team_making_phase?
        status = "Waiting on #{self.team_leader.user} to propose a team of #{self.current_team_size}"
      elsif @current_round.in_team_proposed_phase?
        proposed_team = @current_round.team.players.map(&:user).join(', ')
        status = "Team proposed: #{proposed_team} - Waiting on #{self.team_leader.user} to confirm or choose a new team"
      elsif @current_round.in_vote_phase?
        status = "Waiting on players to vote: #{self.not_voted.map(&:user).join(", ")}"
      elsif @current_round.in_mission_phase?
        status = "Waiting on players to return from the mission: #{self.not_back_from_mission.map(&:user).join(", ")}"
      elsif @current_round.in_assassinate_phase?
        status = "Waiting on the assassin to choose a target"
      end
    else
      if self.player_count.zero?
        status = "No game in progress."
      else
        status = "A game is forming. #{player_count} players have joined: #{self.players.map(&:user).join(", ")}"
      end
    end
    status
  end

  def mission_results
    self.rounds.map { |r| r.mission_success? }
  end

  def is_over?
    self.spies_win? || self.resistance_win?
  end

  def spies_win?
    @current_round.too_many_fails? || self.mission_results.count(false) == 3
  end

  def resistance_win?
    self.mission_results.count(true) == 3
  end

  def start_new_round
    @current_round.end_round
    new_round = self.current_round.number + 1
    @current_round = Round.new(new_round)
    self.rounds << @current_round
    self.assign_team_leader
    if self.variants.include?(:lancelot1)
      if @current_round.number > 2
        @current_round.lancelot_card = self.lancelot_deck.pop
        if @current_round.lancelots_switch?
          self.switch_lancelots
        end
        puts "="*80
        puts self.lancelot_deck.inspect
        puts "="*80
      end
    end
  end


  #----------------------------------------------
  # Helpers 
  #----------------------------------------------

  def player_count
    self.players.count
  end

  def current_round
    @current_round
  end

  def current_team_size
    TEAM_SIZES[self.player_count][@current_round.number]
  end

  def original_spies
    self.players.select{ |p| p.original_spy? }
  end

  def spies
    self.players.select{ |p| p.spy? }
  end

  def resistance
    self.players.select{ |p| p.resistance? }
  end

  def find_player(user)
    self.players.find{ |p| p.user == user }
  end

  def team_sizes
    TEAM_SIZES[self.player_count]
  end

  def get_prev_round(number)
    round = self.rounds.find{ |r| r.number == number }

    #(!(round.nil?) && round.ended? ) ? round : nil
  end

  def game_length
    (self.time_end.nil? || self.time_start.nil?) ? 0 : (self.time_end - self.time_start)
  end

  #----------------------------------------------
  # Find by role
  #----------------------------------------------

  def find_player_by_role(role)
    self.players.find{ |p| p.loyalty == role }
  end

  #----------------------------------------------
  # Current Round Proxies
  #----------------------------------------------
  
  def team_leader
    @current_round.team_leader
  end

  def go_on_mission
    @current_round.go_on_mission    
  end

  def assassinate
    @current_round.assassinate
  end


end

#================================================================================
# ROUNDS
#================================================================================

class Round

  attr_accessor :teams, :number, :mission_votes, :state, :lancelot_card  

  def initialize(number)
    self.state           = :team_making # team_making, team_confirm, vote, mission, lady, (assassinate), end
    self.number          = number
    self.teams           = [Team.new]
    self.mission_votes   = {}
    self.lancelot_card   = nil
  end

  # the current round team is the last team
  def team
    self.teams.last
  end

  # proxy for team team leader
  def team_leader
    self.team.team_leader
  end

  def lancelots_switch?
    self.lancelot_card == :switch
  end

  def fail_count
    self.teams.size - 1
  end

  def too_many_fails?
    self.fail_count >= 5 
  end

  def hammer_team?
    self.fail_count == 4
  end

  def team_makes?
    self.team.team_makes?
  end

  def make_new_team
    self.teams << Team.new
  end

  # Mission methods

  def mission_success?
    mission_score = self.mission_fails
    if mission_score.nil?
      success = nil
    else
      if self.special_round?
        success = mission_score < 2 # need 2 fails
      else
        success = mission_score < 1 # otherwise need 1 fail
      end
    end 
    success
  end

  def mission_fails
    mission_votes.values.map{|mv| mv == 'fail' ? 1 : 0 }.reduce(:+) 
  end


  def special_round?
    $player_count >= 7 && self.number == 4
  end

  # State methods

  def in_team_making_phase?
    self.state == :team_making
  end

  def in_team_proposed_phase?
    self.state == :team_proposed
  end

  def in_vote_phase?
    self.state == :vote
  end

  def in_mission_phase?
    self.state == :mission
  end

  def in_assassinate_phase?
    self.state == :assassinate
  end

  def in_lady_phase?
    self.state == :lady
  end

  def ended?
    self.state == :end
  end


  def back_to_team_making
    self.state = :team_making
  end

  def team_proposed
    self.state = :team_proposed
  end

  def call_for_votes
    self.state = :vote
  end

  def go_on_mission
    self.state = :mission
  end

  def assassinate
    self.state = :assassinate
  end

  def lady_time
    self.state = :lady
  end

  def end_round
    self.state = :end
  end


end


#================================================================================
# TEAM
#================================================================================

class Team

  attr_accessor :team_leader, :players, :team_votes

  def initialize
    self.team_leader = nil
    self.team_votes  = {}
    self.players     = []
  end

  def assign_team_leader(player)
    self.team_leader = player
  end

  def add_to_team(player)
    self.players << player
  end

  def clear_team
    self.players = []
  end

  def size
    self.players.length
  end

  def add_vote(player, vote)
    self.team_votes[player] = vote
  end

  def remove_vote(player)
    self.team_votes.delete(player)
  end

  def voted
    self.team_votes.keys
  end

  def team_makes?
    votes = self.team_votes.values
    votes.count('yes') > votes.count('no')
  end

end


#================================================================================
# PLAYER
#================================================================================

class Player

  attr_accessor :loyalty, :user, :lancelot_switch

  def initialize(user)
    self.user = user
    self.loyalty = nil
    self.lancelot_switch = false
  end 

  def switch_allegiance
    if self.loyalty == :good_lancelot || self.loyalty == :evil_lancelot
      self.lancelot_switch = (self.lancelot_switch == true ? false : true)
    end
  end

  def receive_loyalty(loyalty)
    self.loyalty = loyalty
  end

  def original_spy?
    [:spy, :assassin, :mordred, :oberon, :morgana, :evil_lancelot].any?{ |role| role == self.loyalty }
  end

  def spy?
    [:spy, :assassin, :mordred, :oberon, :morgana].any?{ |role| role == self.loyalty } || (self.loyalty == :good_lancelot && self.lancelot_switch) || (self.loyalty == :evil_lancelot && !self.lancelot_switch )
  end

  def resistance?
    [:resistance, :merlin, :percival].any?{ |role| role == self.loyalty } || (self.loyalty == :evil_lancelot && self.lancelot_switch) || (self.loyalty == :good_lancelot && !self.lancelot_switch )
  end
  
  def role?(role)
    self.loyalty == role
  end

end






