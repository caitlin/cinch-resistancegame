#================================================================================
# ROUNDS
#================================================================================

class Round

  attr_accessor :teams, :number, :mission_votes, :state, :excalibured, :trapped, :lancelot_card

  def initialize(number)
    self.state           = :team_making # team_making, team_confirm, vote, mission, excalibur, lady, (assassinate), end
    self.number          = number
    self.teams           = [Team.new]
    self.mission_votes   = {}
    self.lancelot_card   = nil
    self.excalibured     = nil
    self.trapped         = nil
  end

  # the current round team is the last team
  def team
    self.teams.last
  end

  # proxy for team team leader
  def team_leader
    self.team.team_leader
  end

  def excalibur_holder
    self.team.excalibur
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

  def special_round?
    $player_count >= 7 && self.number == 4
  end

  def make_new_team
    self.teams << Team.new
  end


  #================================================================================
  # Mission methods
  #================================================================================

  def use_trap_on(player)
    self.trapped = player
    return self.mission_votes.delete(player)
  end

  def use_excalibur_on(player)
    self.excalibured = player
    old_vote = self.mission_votes[player]
    # Intentionally not handling 'reverse' here because Excalibur+Reverser should not mix.
    # If we want to be smart, we can have it always switch to "the other card this player should play", but it is questionable.
    # If we do that, we SHOULD NOT reveal the new vote to the Excalibur user, as we currently do (Search for new_vote in ResistanceGame)
    if old_vote == 'fail'
      self.mission_votes[player] = 'pass' 
    elsif old_vote == 'pass'
      self.mission_votes[player] = 'fail'
    end
  end

  def mission_vote_for(player)
    self.mission_votes[player]
  end

  def mission_success?
    mission_score = self.mission_fails
    if mission_score.nil?
      return nil
    else
      if self.special_round?
        success = mission_score < 2 # need 2 fails
      else
        success = mission_score < 1 # otherwise need 1 fail
      end
    end 

    # An odd number of Reverse cards will reverse it. An even number cancels out!
    reverse_it = self.mission_reverses % 2 == 1
    return reverse_it ? !success : success
  end

  def mission_fails
    mission_votes.values.map{|mv| mv == 'fail' ? 1 : 0 }.reduce(:+) 
  end

  def mission_reverses
    mission_votes.values.count { |mv| mv == 'reverse' }
  end



  #================================================================================
  # State methods
  #================================================================================

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

  def in_trapper_phase?
    self.state == :trapper
  end

  def in_excalibur_phase?
    self.state == :excalibur
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

  def ask_for_trapper
    self.state = :trapper
  end

  def ask_for_excalibur
    self.state = :excalibur
  end

  def assassinate
    self.state = :assassinate
  end

  def lady_time
    self.state = :lady
  end

  def lock_decisions
    self.state = :decisions_locked
  end

  def end_round
    self.state = :end
  end


end
