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

  attr_accessor :started, :players, :rounds, :type, :roles, :variants, :lancelot_deck, :lady_token, :assassin_dual, :invitation_sent, :time_start, :time_end
  
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
    # If non-nil, Assassin is dual-classed as this role.
    # If nil, Assassin is its own role.
    self.assassin_dual   = nil
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
    self.roles = options[:roles].map(&:to_sym)
    if type == :avalon
      self.variants = options[:variants].map(&:to_sym)
      self.assassin_dual = options[:assassin_dual] && options[:assassin_dual].to_sym
    else
      self.variants = options[:variants].map(&:to_sym)
    end    
  end

  def avalon?
    self.type == :avalon
  end

  def with_variant?(variant)
    self.variants.include?(variant)
  end

  def with_role?(role)
    self.roles.include?(role)
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
    self.make_lancelot_deck if self.variants.include?(:lancelot1) || self.variants.include?(:lancelot2)
    @current_round = Round.new(1)
    self.rounds << @current_round
    self.players.shuffle!.rotate!(rand(MAX_PLAYERS)) # shuffle seats
    self.assign_team_leader
    self.give_lady_to(self.players.last) if self.variants.include?(:lady)
    $player_count = self.player_count
  end

  def save_game(directory)
    #output = File.new("#{directory}/#{Time.now.to_s}", 'w')
    #output.puts YAML.dump(self)
    #output.close
  end

  def assign_loyalties
    # get appropriate number of each loyalty per player count
    loyalties = LOYALTIES[self.players.count]
    resistance_count = loyalties[:resistance]
    spy_count = loyalties[:spies]

    loyalty_deck = []

    # add roles - this could be done way better probably
    if self.avalon?
      loyalty_deck << :merlin
      resistance_count -= 1

      if self.assassin_dual.nil?
        loyalty_deck << :assassin
        spy_count -= 1
      end

      if self.variants.include?(:lancelot1) || self.variants.include?(:lancelot2) || self.variants.include?(:lancelot3)
        loyalty_deck << :good_lancelot
        resistance_count -= 1
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

    if self.roles.include?(:resistance_reverser)
      loyalty_deck << :resistance_reverser
      resistance_count -= 1
    end
    if self.roles.include?(:spy_reverser)
      loyalty_deck << :spy_reverser
      spy_count -= 1
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
    if self.variants.include?(:lancelot1)
      self.lancelot_deck << [:switch] * 2
      self.lancelot_deck << [:no_switch] * 3
      self.lancelot_deck.flatten!.shuffle!
    elsif self.variants.include?(:lancelot2)
      self.lancelot_deck << [:switch] * 2
      self.lancelot_deck << [:no_switch] * 5
      self.lancelot_deck.flatten!.shuffle!
    end
  end

  def lancelots_switched?
    self.lancelot_deck.count(:switch) % 2 == 1
  end

  def play_lancelot_card
    return unless self.variants.include?(:lancelot1) && @current_round.number > 2 || self.variants.include?(:lancelot2)

    @current_round.lancelot_card = self.lancelot_deck.pop
    self.switch_lancelots if @current_round.lancelots_switch?
  end

  def switch_lancelots
    good_lancelot = self.find_player_by_role(:good_lancelot)
    evil_lancelot = self.find_player_by_role(:evil_lancelot)
    good_lancelot.switch_allegiance
    evil_lancelot.switch_allegiance
  end

  def give_lady_to(player)
    self.lady_token = player
    player.lady!
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
    self.play_lancelot_card
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
    base = TEAM_SIZES[self.player_count][@current_round.number]
    return base + (with_variant?(:trapper) ? 1 : 0)
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

  def find_assassin
    assassin = self.assassin_dual || :assassin
    self.find_player_by_role(assassin)
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






