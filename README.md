# Cinch-BGG - BoardGameGeek plugin

## Description

This is a Cinch plugin to enable your bot to moderate The Resistance by Don Eskridge. 

http://boardgamegeek.com/boardgame/41114/the-resistance

## Usage

Here's an example of what your *bot.rb* might look like: 

    require 'cinch'
    require './cinch-resistancegame/lib/cinch/plugins/resistance_game'

    bot = Cinch::Bot.new do

      configure do |c|
        c.nick            = "ResistanceBotDev"
        c.server          = "irc.freenode.org"
        c.channels        = ["#playresistance"]
        c.verbose         = true
        c.plugins.plugins = [
          Cinch::Plugins::ResistanceGame,
          Cinch::Plugins::Identify
        ]
        c.plugins.options[Cinch::Plugins::ResistanceGame] = {
          :mods     => ["caitlinface", "timotab", "JohnnyWarpzone", "Chank"],
          :channel  => "#playresistance",
          :settings => "settings.yml"
        }
      end

    end

    bot.start

## Development

https://www.pivotaltracker.com/projects/642861