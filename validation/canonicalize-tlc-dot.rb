#!/usr/bin/env ruby
require "json"
input, output = ARGV
abort "Usage: #{$PROGRAM_NAME} <graph.dot> <canonical-graph.json>" unless input && output && ARGV.length == 2
states, initial, edges = {}, [], []
File.foreach(input) do |line|
  if (match = line.match(/^(-?\d+) \[label="((?:\\.|[^"])*)"/))
    states[match[1]] = match[2]
    initial << match[2] if line.include?("style = filled")
  elsif (match = line.match(/^(-?\d+) -> (-?\d+) \[label="((?:\\.|[^"])*)",/))
    edges << match.captures
  end
end
abort "No TLC states were found in #{input}" if states.empty?
canonical = edges.map { |from, to, action| abort "Unknown TLC state" unless states[from] && states[to]; { "from" => states[from], "action" => action, "to" => states[to] } }.sort_by { |edge| [edge["from"], edge["action"], edge["to"]] }
File.write(output, JSON.generate({ "schema" => "TLCActionLabelDOTGraphV1", "initialStates" => initial.sort, "states" => states.values.sort, "edges" => canonical }) + "\n")
