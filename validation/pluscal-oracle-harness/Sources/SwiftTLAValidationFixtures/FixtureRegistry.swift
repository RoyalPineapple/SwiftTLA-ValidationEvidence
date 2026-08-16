import SwiftTLA

/// One bounded consumer fixture checked by independent external lowerings.
/// This is validation policy and intentionally is not a SwiftTLA public API.
public struct OracleFixture: Sendable {
    public let id: String
    public let swiftConfiguration: String
    public let plusCalConfiguration: String
    private let makeSpecification: @Sendable () -> TLASpec

    public init(
        id: String,
        swiftConfiguration: String,
        plusCalConfiguration: String? = nil,
        specification: @escaping @Sendable () -> TLASpec
    ) {
        self.id = id
        self.swiftConfiguration = swiftConfiguration
        self.plusCalConfiguration = plusCalConfiguration ?? swiftConfiguration
        makeSpecification = specification
    }

    public func specification() -> TLASpec {
        makeSpecification()
    }

    public func plusCalModule() throws -> String {
        let modules = try specification().renderAuthoredPlusCalModules()
        guard modules.count == 1 else {
            throw OracleFixtureDiagnostic(
                failedConcept: "PlusCal oracle fixture source",
                fixtureID: id,
                expected: "exactly one authored Algorithm module",
                actual: "\(modules.count) authored Algorithm modules",
                nextSafeAction: "Give this fixture one #spec Algorithm, or split independent Algorithms into separate fixtures."
            )
        }
        return modules[0]
    }
}

public struct OracleFixtureDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public let failedConcept: String
    public let fixtureID: String
    public let expected: String
    public let actual: String
    public let nextSafeAction: String

    public var description: String {
        "\(failedConcept) for '\(fixtureID)': expected \(expected); found \(actual). "
            + "System change: none. Next safe action: \(nextSafeAction)"
    }
}

/// The intentionally small independent PlusCal oracle corpus.
public enum OracleFixtureRegistry {
    public static let scopeBindingSubstitution = OracleFixture(
        id: "scope-binding-substitution",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { ScopeBindingSubstitutionWitness.spec }
    )
    public static let formalOperatorValues = OracleFixture(
        id: "formal-operator-values",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { FormalOperatorValuesWitness.spec }
    )
    public static let simultaneousAssignment = OracleFixture(
        id: "simultaneous-assignment",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { SimultaneousAssignmentWitness.spec }
    )
    public static let structuredRecordFunctions = OracleFixture(
        id: "structured-record-functions",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { StructuredRecordFunctionsWitness.spec }
    )
    public static let procedureCallReturn = OracleFixture(
        id: "procedure-call-return",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        plusCalConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nCONSTANT defaultInitValue = 0\n",
        specification: { ProcedureCallReturnWitness.spec }
    )
    public static let boulangerUpstreamPort = OracleFixture(
        id: "boulanger-upstream-port",
        swiftConfiguration: "SPECIFICATION Spec\nCONSTRAINT StateConstraint\n",
        specification: { BoulangerWitness.spec }
    )
    public static let kvsnapUpstreamPort = OracleFixture(
        id: "kvsnap-upstream-port",
        swiftConfiguration: "SPECIFICATION Spec\nINVARIANTS TypeOK SnapshotIsolation\nPROPERTIES Termination\nCONSTANT k1 = k1\nCONSTANT k2 = k2\nCONSTANT t1 = t1\nCONSTANT t2 = t2\nCONSTANT t3 = t3\nCONSTANT NoVal = NoVal\n",
        specification: { KVsnapWitness.spec }
    )
    public static let fixtures = [
        scopeBindingSubstitution,
        formalOperatorValues,
        simultaneousAssignment,
        structuredRecordFunctions,
        procedureCallReturn,
        boulangerUpstreamPort,
        kvsnapUpstreamPort
    ]

    public static func fixture(id: String) -> OracleFixture? {
        fixtures.first { $0.id == id }
    }
}
