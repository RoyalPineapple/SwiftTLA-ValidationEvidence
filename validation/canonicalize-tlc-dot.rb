#!/usr/bin/env ruby
require "json"
input, output = ARGV
abort "Usage: #{$PROGRAM_NAME} <graph.dot> <canonical-graph.json>" unless input && output && ARGV.length == 2
states, initial, edges = {}, [], []
def canonical_state_label(label)
  bindings = label.split("\\n/\\ ").each_with_index.map do |conjunct, index|
    conjunct = "/\\ #{conjunct}" unless index.zero?
    match = conjunct.match(/\A\/\\\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\z/)
    return label unless match
    [match[1], conjunct]
  end
  return label unless bindings.map(&:first).uniq.length == bindings.length
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
canonical = edges.map { |from, to, action| abort "Unknown TLC state" unless states[from] && states[to]; { "from" => states[from], "action" => action, "to" => states[to] } }.uniq.sort_by { |edge| [edge["from"], edge["action"], edge["to"]] }
File.write(output, JSON.generate({ "schema" => "TLCActionLabelDOTGraphV2", "initialStates" => initial.sort, "states" => states.values.sort, "edgeCounts" => { "rawRecords" => edges.length, "uniqueRelations" => canonical.length }, "edges" => canonical }) + "\n")
