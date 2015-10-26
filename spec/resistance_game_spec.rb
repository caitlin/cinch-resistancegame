require 'simplecov'
SimpleCov.start { add_filter '/spec/' }

require 'cinch/test'
require 'cinch/plugins/resistance_game'

RSpec.configure { |c|
  c.warnings = true
  c.disable_monkey_patching!
}

class MessageReceiver
  attr_reader :name
  attr_accessor :messages

  def initialize(name)
    @name = name
    @messages = []
  end

  def send(m)
    @messages << m
  end
end

class TestChannel < MessageReceiver
end

def get_replies_text(m)
  replies = get_replies(m)
  # If you wanted, you could read all the messages as they come, but that might be a bit much.
  # You'd want to check the messages of user1, user2, and chan as well.
  # replies.each { |x| puts(x.text) }
  replies.map(&:text)
end

RSpec::describe Cinch::Plugins::ResistanceGame do
  include Cinch::Test

  let(:channel1) { '#testchannel' }
  let(:chan) { TestChannel.new(channel1) }
  let(:players) { (1..5).map { |x| "player#{x}" } }
  let(:npmod) { 'npmod' }

  let(:opts) {{
    :channel => channel1,
    :settings => '/dev/null',
    :mods => [npmod, players[0]],
    :allowed_idle => 300,
  }}

  let(:bot) {
    make_bot(described_class, opts) { |c|
      self.loggers.first.level = :warn
    }
  }
  let(:plugin) { bot.plugins.first }

  def msg(text, nick: players[0], channel: channel1)
    make_message(bot, text, nick: nick, channel: channel)
  end
  def join(player)
    message = msg('!join', nick: player)
    allow(plugin).to receive(:Channel).with(channel1).and_return(chan)
    expect(chan).to receive(:has_user?).with(message.user).and_return(true)
    expect(chan).to receive(:voice).with(message.user)
    get_replies(message)
  end

  it 'makes a test bot' do
    expect(bot).to be_a(Cinch::Bot)
  end

  context 'in game' do
    before(:each) do
      players.each { |player| join(player) }
      chan.messages.clear
      get_replies(msg('!start'))
      chan.messages.grep(/Player order is: (.*)/) { |msg| @order = Regexp.last_match(1).split }
      @leader = @order.first
      chan.messages.clear
    end

    it 'allows leader to select team' do
      get_replies(msg('!team player1 player2', nick: @leader))
      expect(chan.messages).to be == ["#{@leader} is proposing the team: player1, player2."]
    end

    it 'allows leader to select team twice' do
      get_replies(msg('!team player1 player2', nick: @leader))
      chan.messages.clear
      get_replies(msg('!team player3 player4', nick: @leader))
      expect(chan.messages).to be == ["#{@leader} is proposing the team: player3, player4."]
    end

    it 'allows leader to confirm team' do
      get_replies(msg('!team player1 player2', nick: @leader))
      chan.messages.clear
      get_replies(msg('!confirm', nick: @leader))
      expect(chan.messages).to be == ['The proposed team: player1, player2. Time to vote!']
    end

    it 'disallows changing mind about team after a confirm' do
      get_replies(msg('!team player1 player2', nick: @leader))
      get_replies(msg('!confirm', nick: @leader))
      chan.messages.clear
      expect(get_replies_text(msg('!team player3 player4', nick: @leader))).to be == [
        "#{@leader}: The team has already been confirmed."
      ]
      expect(chan.messages).to be_empty
    end
  end
end
