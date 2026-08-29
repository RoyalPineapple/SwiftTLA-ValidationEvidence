#!/usr/bin/env ruby
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

root = __dir__
Dir.mktmpdir do |directory|
  canonicalize = lambda do |name, dot|
    input = File.join(directory, "#{name}.dot")
    output = File.join(directory, "#{name}.json")
    File.write(input, dot)
    _, stderr, status = Open3.capture3(RbConfig.ruby, File.join(root, "canonicalize-tlc-dot.rb"), input, output)
    abort stderr unless status.success?
    JSON.parse(File.read(output))
  end
  semantic_projection = ->(graph) { graph.slice("schema", "version", "initialStates", "states", "edges") }

  duplicate_graph = canonicalize.call("duplicate", <<~DOT)
    0 [label="start",style = filled];
    1 [label="done"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="retry",color="black"];
  DOT
  missing_repeated_edge = canonicalize.call("missing-repeated-edge", <<~DOT)
    0 [label="start",style = filled];
    1 [label="done"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="retry",color="black"];
  DOT
  different_graph = canonicalize.call("different", <<~DOT)
    0 [label="start",style = filled];
    1 [label="done"];
    0 -> 1 [label="advance",color="black"];
  DOT
  reordered_bindings = canonicalize.call("reordered-bindings", <<~DOT)
    0 [label="/\\\\ x = 1\\n/\\\\ y = 2",style = filled];
    1 [label="/\\\\ x = 2\\n/\\\\ y = 3"];
    0 -> 1 [label="advance",color="black"];
  DOT
  ordered_bindings = canonicalize.call("ordered-bindings", <<~DOT)
    0 [label="/\\\\ y = 2\\n/\\\\ x = 1",style = filled];
    1 [label="/\\\\ y = 3\\n/\\\\ x = 2"];
    0 -> 1 [label="advance",color="black"];
  DOT
  changed_binding = canonicalize.call("changed-binding", <<~DOT)
    0 [label="/\\\\ y = 2\\n/\\\\ x = 1",style = filled];
    1 [label="/\\\\ y = 4\\n/\\\\ x = 2"];
    0 -> 1 [label="advance",color="black"];
  DOT
  reordered_multiline_bindings = canonicalize.call("reordered-multiline-bindings", <<~DOT)
    0 [label="/\\\\ snapshotStore = [k1 |-> NoVal\\n  k2 |-> NoVal]\\n/\\\\ tx = {}",style = filled];
    1 [label="/\\\\ snapshotStore = [k1 |-> t1\\n  k2 |-> NoVal]\\n/\\\\ tx = {}"];
    0 -> 1 [label="advance",color="black"];
  DOT
  ordered_multiline_bindings = canonicalize.call("ordered-multiline-bindings", <<~DOT)
    0 [label="/\\\\ tx = {}\\n/\\\\ snapshotStore = [k1 |-> NoVal\\n  k2 |-> NoVal]",style = filled];
    1 [label="/\\\\ tx = {}\\n/\\\\ snapshotStore = [k1 |-> t1\\n  k2 |-> NoVal]"];
    0 -> 1 [label="advance",color="black"];
  DOT

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
end
