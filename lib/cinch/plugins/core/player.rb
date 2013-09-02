#================================================================================
# PLAYER
#================================================================================

class Player

  attr_accessor :loyalty, :user, :lancelot_switch, :ladied

  def initialize(user)
    self.user = user
    self.loyalty = nil
    self.lancelot_switch = false
    self.ladied = false
  end 

  def switch_allegiance
    if self.loyalty == :good_lancelot || self.loyalty == :evil_lancelot
      self.lancelot_switch = !self.lancelot_switch
    end
  end

  def receive_loyalty(loyalty)
    self.loyalty = loyalty
  end

  def lady!
    self.ladied = true
  end

  def ladied?
    self.ladied == true
  end

  def original_spy?
    [:spy, :assassin, :mordred, :oberon, :morgana, :evil_lancelot].any?{ |role| role == self.loyalty }
  end

  def currently_evil_lancelot?
    self.loyalty == :good_lancelot && self.lancelot_switch || self.loyalty == :evil_lancelot && !self.lancelot_switch
  end

  def spy?
    [:spy, :assassin, :mordred, :oberon, :morgana].any?{ |role| role == self.loyalty } || self.currently_evil_lancelot?
  end

  def resistance?
    [:resistance, :merlin, :percival].any?{ |role| role == self.loyalty } || (self.loyalty == :evil_lancelot && self.lancelot_switch) || (self.loyalty == :good_lancelot && !self.lancelot_switch )
  end
  
  def role?(role)
    self.loyalty == role
  end

end

