# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "cinch-resistance"
  s.version     = "1.0"
  s.platform    = Gem::Platform::RUBY
  s.homepage    = "https://github.com/caitlin/cinch-resistancegame"
  s.authors     = ['caitlin']
  s.summary     = %q{Gives Cinch IRC bots ability to play The Resistance}
  s.description = %q{Gives Cinch IRC bots ability to play The Resistance}

  s.add_dependency("cinch", "~> 2.0")
  s.add_dependency("amatch")

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]
end
