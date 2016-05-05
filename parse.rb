require './parser.rb'
require 'pp'

p = Parser.parse(File.open(ARGV[0]))

pp p
