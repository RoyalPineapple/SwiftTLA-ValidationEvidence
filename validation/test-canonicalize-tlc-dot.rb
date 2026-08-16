#!/usr/bin/env ruby
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

root = __dir__
Dir.mktmpdir do |directory|
  input = File.join(directory, "graph.dot")
  output = File.join(directory, "canonical.json")
  File.write(input, <<~DOT)
    0 [label="start",style = filled];
    1 [label="done"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="advance",color="black"];
    0 -> 1 [label="retry",color="black"];
  DOT
  _, stderr, status = Open3.capture3(RbConfig.ruby, File.join(root, "canonicalize-tlc-dot.rb"), input, output)
  abort stderr unless status.success?
  graph = JSON.parse(File.read(output))
  abort "duplicate edge was not collapsed" unless graph.fetch("edgeCounts") == { "rawRecords" => 3, "uniqueRelations" => 2 }
  abort "action labels were not retained" unless graph.fetch("edges") == [{ "from" => "start", "action" => "advance", "to" => "done" }, { "from" => "start", "action" => "retry", "to" => "done" }]
end
