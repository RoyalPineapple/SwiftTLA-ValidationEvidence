import AlgorithmConformance
import CryptoKit
import Foundation

struct Metadata: Encodable {
    let schema = "SwiftTLAPlusCalFixtureExportV1"
    let fixtureID: String
    let swiftTLACommit: String
    let inputSHA256: [String: String]
}

func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

let arguments = CommandLine.arguments
if arguments.count == 2, arguments[1] == "--list" {
    print(AlgorithmConformanceRegistry.fixtures.map(\.id).joined(separator: "\n"))
    exit(0)
}
guard arguments.count == 4, let fixture = AlgorithmConformanceRegistry.fixture(id: arguments[1]) else {
    fputs("Usage: pluscal-oracle-harness <fixture-id> <fresh-output-directory> <full-swifttla-sha>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[2])
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    let direct = fixture.specification().tlaModule
    let config = fixture.configuration
    let plusCal = try fixture.plusCalModule()
    try Data(direct.utf8).write(to: output.appendingPathComponent("swift-lowered.tla"), options: .atomic)
    try Data(config.utf8).write(to: output.appendingPathComponent("model.cfg"), options: .atomic)
    try Data(plusCal.utf8).write(to: output.appendingPathComponent("pluscal-source.tla"), options: .atomic)
    let metadata = Metadata(fixtureID: fixture.id, swiftTLACommit: arguments[3], inputSHA256: [
        "swift-lowered.tla": digest(direct), "model.cfg": digest(config), "pluscal-source.tla": digest(plusCal)
    ])
    try JSONEncoder().encode(metadata).write(to: output.appendingPathComponent("metadata.json"), options: .atomic)
} catch {
    fputs("fixture export failed: \(error)\n", stderr)
    exit(2)
}
