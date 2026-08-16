import SwiftTLAValidationFixtures
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
    print(OracleFixtureRegistry.fixtures.map(\.id).joined(separator: "\n"))
    exit(0)
}
guard arguments.count == 4, let fixture = OracleFixtureRegistry.fixture(id: arguments[1]) else {
    fputs("Usage: pluscal-oracle-harness <fixture-id> <fresh-output-directory> <full-swifttla-sha>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[2])
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    let direct = fixture.specification().tlaModule
    let swiftConfiguration = fixture.swiftConfiguration
    let plusCalConfiguration = fixture.plusCalConfiguration
    let plusCal = try fixture.plusCalModule()
    try Data(direct.utf8).write(to: output.appendingPathComponent("swift-lowered.tla"), options: .atomic)
    try Data(swiftConfiguration.utf8).write(to: output.appendingPathComponent("swift.cfg"), options: .atomic)
    try Data(plusCal.utf8).write(to: output.appendingPathComponent("pluscal-source.tla"), options: .atomic)
    try Data(plusCalConfiguration.utf8).write(to: output.appendingPathComponent("pluscal.cfg"), options: .atomic)
    let metadata = Metadata(fixtureID: fixture.id, swiftTLACommit: arguments[3], inputSHA256: [
        "swift-lowered.tla": digest(direct),
        "swift.cfg": digest(swiftConfiguration),
        "pluscal-source.tla": digest(plusCal),
        "pluscal.cfg": digest(plusCalConfiguration)
    ])
    try JSONEncoder().encode(metadata).write(to: output.appendingPathComponent("metadata.json"), options: .atomic)
} catch {
    fputs("fixture export failed: \(error)\n", stderr)
    exit(2)
}
