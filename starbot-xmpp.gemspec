require File.expand_path("../lib/starbot/xmpp", __FILE__)
require "rubygems"
::Gem::Specification.new do |s|
  s.name                        = 'starbot-xmpp'
  s.version                     = Starbot::Xmpp::VERSION
  s.platform                    = ::Gem::Platform::RUBY
  s.authors                     = ['Gavin Brock', 'Caleb Crane', 'Eric Platon']
  s.email                       = ["starbot@simulacre.org"]
  s.homepage                    = "http://www.github.com/simulacre/simbot"
  s.summary                     = 'Starbot rocks'
  s.description                 = 'Starbot answers questions and volunteers information'
  s.required_rubygems_version   = ">= 1.3.6"
  s.rubyforge_project           = 'starbot-skype'
  s.files                       = Dir["lib/**/*.rb", "bin/*", "*.md"]
  s.require_paths               = ['lib']
  s.executables                 = Dir["bin/*"].map{|f| f.split("/")[-1] }

  #s.add_dependency 'starbot'
  s.add_dependency 'xmpp4r'
end