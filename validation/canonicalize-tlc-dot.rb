#!/usr/bin/env ruby
require "json"

input, output = ARGV
abort "Usage: #{$PROGRAM_NAME} <graph.dot> <canonical-graph.json>" unless input && output && ARGV.length == 2

header = [
  "strict digraph DiskGraph {",
  "node [shape=box,style=rounded]",
  "nodesep=0.35;",
  "subgraph cluster_graph {",
  "color=\"white\";"
]
states = {}
initial_ids = []
edges = []
rank_ids = []

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

phase = :header
header_index = 0
File.foreach(input).with_index(1) do |raw_line, line_number|
  line = raw_line.chomp("\n")
  case phase
  when :header
    abort "Invalid TLC DOT graph header" unless line == header[header_index]
    header_index += 1
    phase = :records if header_index == header.length
  when :records
    if line == "}"
      phase = :outer_close
      next
    end
    case line
    when /\A(-?\d+) \[label="((?:\\.|[^"])*)",style = filled\];?\z/
      id, label = Regexp.last_match.captures
      abort "Duplicate TLC state ID #{id} at line #{line_number}" if states.key?(id)
      states[id] = canonical_state_label(label)
      initial_ids << id
    when /\A(-?\d+) \[label="((?:\\.|[^"])*)",tooltip="((?:\\.|[^"])*)"\];\z/
      id, label, tooltip = Regexp.last_match.captures
      abort "TLC state tooltip differs at line #{line_number}" unless tooltip == label
      abort "Duplicate TLC state ID #{id} at line #{line_number}" if states.key?(id)
      states[id] = canonical_state_label(label)
    when /\A(-?\d+) -> (-?\d+) \[label="((?:\\.|[^"])*)",color="black",fontcolor="black"\];\z/
      edges << Regexp.last_match.captures
    when /\A\{rank = same; ((?:-?\d+;)*)\}\z/
      rank_ids.concat(Regexp.last_match(1).scan(/-?\d+/))
    else
      abort "Unrecognized TLC DOT record at line #{line_number}: #{line}"
    end
  when :outer_close
    abort "Incomplete TLC DOT graph" unless line == "}"
    phase = :done
  when :done
    abort "Incomplete TLC DOT graph"
  end
end
abort(phase == :header ? "Invalid TLC DOT graph header" : "Incomplete TLC DOT graph") unless phase == :done

abort "No TLC states were found in #{input}" if states.empty?
abort "No TLC initial state was found in #{input}" if initial_ids.empty?
abort "TLC rank references an unknown state" unless rank_ids.all? { |id| states.key?(id) }

edge_occurrences = edges.each_with_object(Hash.new(0)) do |(from, to, action), counts|
  abort "TLC edge references an unknown state" unless states[from] && states[to]
  counts[{ "from" => states[from], "action" => action, "to" => states[to] }] += 1
end
canonical = edge_occurrences.map { |edge, occurrences| edge.merge("occurrences" => occurrences) }
  .sort_by { |edge| [edge["from"], edge["action"], edge["to"]] }
File.write(output, JSON.generate({
  "schema" => "TLCActionLabelDOTGraph",
  "version" => 1,
  "initialStates" => initial_ids.map { |id| states.fetch(id) }.sort,
  "states" => states.values.sort,
  "edges" => canonical
}) + "\n")
