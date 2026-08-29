#!/usr/bin/env ruby
require "json"
input, output = ARGV
abort "Usage: #{$PROGRAM_NAME} <graph.dot> <canonical-graph.json>" unless input && output && ARGV.length == 2
states, initial, edges = {}, [], []
def canonical_state_label(label)
  bindings = label.split("\\n/\\\\ ").each_with_index.map do |conjunct, index|
    conjunct = "/\\\\ #{conjunct}" unless index.zero?
    match = conjunct.match(/\A\/\\\\\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/)
    return label unless match
    [match[1], conjunct]
  end
  return label unless bindings.group_by(&:first).values.all?(&:one?)
  bindings.sort_by(&:first).map(&:last).join("\\n")
end

File.foreach(input) do |line|
  if (match = line.match(/^(-?\d+) \[label="((?:\\.|[^"])*)"/))
    states[match[1]] = canonical_state_label(match[2])
    initial << states[match[1]] if line.include?("style = filled")
  elsif (match = line.match(/^(-?\d+) -> (-?\d+) \[label="((?:\\.|[^"])*)",/))
    edges << match.captures
  end
end
abort "No TLC states were found in #{input}" if states.empty?
edge_occurrences = edges.each_with_object(Hash.new(0)) do |(from, to, action), counts|
  abort "Unknown TLC state" unless states[from] && states[to]
  counts[{ "from" => states[from], "action" => action, "to" => states[to] }] += 1
end
canonical = edge_occurrences.map { |edge, occurrences| edge.merge("occurrences" => occurrences) }
  .sort_by { |edge| [edge["from"], edge["action"], edge["to"]] }
File.write(output, JSON.generate({ "schema" => "TLCActionLabelDOTGraph", "version" => 1, "initialStates" => initial.sort, "states" => states.values.sort, "edges" => canonical }) + "\n")
