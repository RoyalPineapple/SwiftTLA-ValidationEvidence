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
  semantic_projection = ->(graph) { graph.slice("schema", "initialStates", "states", "edges") }

  duplicate_graph = canonicalize.call("duplicate", <<~DOT)
    0 [label="start",style = filled];
    1 [label="done"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="retry",color="black"];
  DOT
  relation_graph = canonicalize.call("relation", <<~DOT)
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
    0 [label="/\\ x = 1\\n/\\ y = 2",style = filled];
    1 [label="/\\ x = 2\\n/\\ y = 3"];
    0 -> 1 [label="advance",color="black"];
  DOT
  ordered_bindings = canonicalize.call("ordered-bindings", <<~DOT)
    0 [label="/\\ y = 2\\n/\\ x = 1",style = filled];
    1 [label="/\\ y = 3\\n/\\ x = 2"];
    0 -> 1 [label="advance",color="black"];
  DOT
  changed_binding = canonicalize.call("changed-binding", <<~DOT)
    0 [label="/\\ y = 2\\n/\\ x = 1",style = filled];
    1 [label="/\\ y = 4\\n/\\ x = 2"];
    0 -> 1 [label="advance",color="black"];
  DOT

  abort "duplicate edge was not collapsed" unless duplicate_graph.fetch("edgeCounts") == { "rawRecords" => 3, "uniqueRelations" => 2 }
  abort "action labels were not retained" unless duplicate_graph.fetch("edges") == [{ "from" => "start", "action" => "advance", "to" => "done" }, { "from" => "start", "action" => "retry", "to" => "done" }]
  abort "unequal raw counts changed the same relation" unless semantic_projection.call(duplicate_graph) == semantic_projection.call(relation_graph)
  abort "semantic edge difference was ignored" if semantic_projection.call(relation_graph) == semantic_projection.call(different_graph)
  abort "top-level binding order was not normalized" unless semantic_projection.call(reordered_bindings) == semantic_projection.call(ordered_bindings)
  abort "changed top-level binding was ignored" if semantic_projection.call(reordered_bindings) == semantic_projection.call(changed_binding)
end
