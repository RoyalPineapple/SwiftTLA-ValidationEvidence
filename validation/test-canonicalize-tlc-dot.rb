#!/usr/bin/env ruby
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

root = __dir__
graph = lambda do |body|
  <<~DOT
    strict digraph DiskGraph {
    node [shape=box,style=rounded]
    nodesep=0.35;
    subgraph cluster_graph {
    color="white";
    #{body}}
    }
  DOT
end

Dir.mktmpdir do |directory|
  run = lambda do |name, dot|
    input = File.join(directory, "#{name}.dot")
    output = File.join(directory, "#{name}.json")
    File.write(input, dot)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, File.join(root, "canonicalize-tlc-dot.rb"), input, output)
    [stdout, stderr, status, output]
  end
  canonicalize = lambda do |name, body|
    _, stderr, status, output = run.call(name, graph.call(body))
    abort stderr unless status.success?
    JSON.parse(File.read(output))
  end
  rejects = lambda do |name, dot, message|
    _, stderr, status, = run.call(name, dot)
    abort "#{name} was accepted" if status.success?
    abort "#{name} reported the wrong failure: #{stderr}" unless stderr.include?(message)
  end
  node = ->(id, label, initial: false) do
    if initial
      %(#{id} [label="#{label}",style = filled]\n)
    else
      %(#{id} [label="#{label}",tooltip="#{label}"];\n)
    end
  end
  edge = ->(from, to, action) do
    %(#{from} -> #{to} [label="#{action}",color="black",fontcolor="black"];\n)
  end
  semantic_projection = ->(value) { value.slice("schema", "version", "initialStates", "states", "edges") }

  duplicate_graph = canonicalize.call("duplicate",
    node.call(0, "start", initial: true) + node.call(1, "done") +
      edge.call(0, 1, "advance") + edge.call(0, 1, "advance") + edge.call(0, 1, "retry") +
      "{rank = same; 0;1;}\n")
  missing_repeated_edge = canonicalize.call("missing-repeated-edge",
    node.call(0, "start", initial: true) + node.call(1, "done") +
      edge.call(0, 1, "advance") + edge.call(0, 1, "retry"))
  different_graph = canonicalize.call("different",
    node.call(0, "start", initial: true) + node.call(1, "done") + edge.call(0, 1, "advance"))
  reordered_bindings = canonicalize.call("reordered-bindings",
    node.call(0, "/\\\\ x = 1\\n/\\\\ y = 2", initial: true) +
      node.call(1, "/\\\\ x = 2\\n/\\\\ y = 3") + edge.call(0, 1, "advance"))
  ordered_bindings = canonicalize.call("ordered-bindings",
    node.call(0, "/\\\\ y = 2\\n/\\\\ x = 1", initial: true) +
      node.call(1, "/\\\\ y = 3\\n/\\\\ x = 2") + edge.call(0, 1, "advance"))
  changed_binding = canonicalize.call("changed-binding",
    node.call(0, "/\\\\ y = 2\\n/\\\\ x = 1", initial: true) +
      node.call(1, "/\\\\ y = 4\\n/\\\\ x = 2") + edge.call(0, 1, "advance"))
  reordered_multiline_bindings = canonicalize.call("reordered-multiline-bindings",
    node.call(0, "/\\\\ snapshotStore = [k1 |-> NoVal\\n  k2 |-> NoVal]\\n/\\\\ tx = {}", initial: true) +
      node.call(1, "/\\\\ snapshotStore = [k1 |-> t1\\n  k2 |-> NoVal]\\n/\\\\ tx = {}") +
      edge.call(0, 1, "advance"))
  ordered_multiline_bindings = canonicalize.call("ordered-multiline-bindings",
    node.call(0, "/\\\\ tx = {}\\n/\\\\ snapshotStore = [k1 |-> NoVal\\n  k2 |-> NoVal]", initial: true) +
      node.call(1, "/\\\\ tx = {}\\n/\\\\ snapshotStore = [k1 |-> t1\\n  k2 |-> NoVal]") +
      edge.call(0, 1, "advance"))
  isolated_initials = canonicalize.call("isolated-initials",
    node.call(0, "first", initial: true) + node.call(1, "second", initial: true) +
      "{rank = same; 0;1;}\n")

  abort "schema identity is not explicit" unless duplicate_graph.slice("schema", "version") == { "schema" => "TLCActionLabelDOTGraph", "version" => 1 }
  abort "labeled edge multiplicity was not retained" unless duplicate_graph.fetch("edges") == [
    { "from" => "start", "action" => "advance", "to" => "done", "occurrences" => 2 },
    { "from" => "start", "action" => "retry", "to" => "done", "occurrences" => 1 }
  ]
  abort "removing one repeated edge did not change the graph" if semantic_projection.call(duplicate_graph) == semantic_projection.call(missing_repeated_edge)
  abort "semantic edge difference was ignored" if semantic_projection.call(missing_repeated_edge) == semantic_projection.call(different_graph)
  abort "top-level binding order was not normalized" unless semantic_projection.call(reordered_bindings) == semantic_projection.call(ordered_bindings)
  abort "changed top-level binding was ignored" if semantic_projection.call(reordered_bindings) == semantic_projection.call(changed_binding)
  abort "multiline binding value prevented top-level normalization" unless semantic_projection.call(reordered_multiline_bindings) == semantic_projection.call(ordered_multiline_bindings)
  abort "multiple initial states or a zero-edge graph changed" unless
    isolated_initials.fetch("initialStates") == ["first", "second"] && isolated_initials.fetch("edges").empty?

  valid = graph.call(node.call(0, "start", initial: true) + node.call(1, "done") + edge.call(0, 1, "advance"))
  rejects.call("truncated", valid.lines[0...-2].join, "Incomplete TLC DOT graph")
  rejects.call("duplicate-state", graph.call(node.call(0, "start", initial: true) + node.call(0, "start")), "Duplicate TLC state ID")
  rejects.call("malformed-edge", graph.call(node.call(0, "start", initial: true) + node.call(1, "done") + "0 -> 1 [label=\"advance\"];\n"), "Unrecognized TLC DOT record")
  rejects.call("unknown-record", graph.call(node.call(0, "start", initial: true) + "edge disappeared here\n"), "Unrecognized TLC DOT record")
  rejects.call("trailing-record", valid + "0 -> 0 [label=\"late\",color=\"black\",fontcolor=\"black\"];\n", "Incomplete TLC DOT graph")
end
