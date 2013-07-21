#================================================================================
# TEAM
#================================================================================

class Team

  attr_accessor :team_leader, :players, :team_votes, :excalibur

  def initialize
    self.team_leader = nil
    self.team_votes  = {}
    self.players     = []
    self.excalibur   = nil
  end

  def has_player?(player)
    self.players.include?(player)
  end

  def assign_team_leader(player)
    self.team_leader = player
  end

  def add_to_team(player)
    self.players << player
  end

  def give_excalibur_to(player)
    self.excalibur = player
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

