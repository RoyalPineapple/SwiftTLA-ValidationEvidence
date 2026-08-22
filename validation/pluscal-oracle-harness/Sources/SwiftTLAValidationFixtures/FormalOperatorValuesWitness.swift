import SwiftTLA

public struct FormalOperatorValuesWitness {
    public enum Worker: String, CaseIterable, FiniteDomainKey {
        case left
        case right

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "k2.scoped-formal-lambda-tlc-witness.worker")

        public var tlaValue: TLAValue { .string(rawValue) }
        public static var defaultValue: Self { .left }

        public init?(formalValue: TLAValue) {
            guard case .string(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    private enum Label: String, PlusCalLabel, CaseIterable {
        case advance
    }

    public static var spec: TLASpec {
        TLASpec("FormalOperatorValuesWitness") {
            Algorithm("FormalOperatorValuesWitness") {
                let counters = SharedVar("counters", initial: Function<Worker, Int>.literal(
                    (.left, 0),
                    (.right, 0)
                ))
                counters

                Each(Worker.all) { worker in
                    Do(Label.advance) {
                        Assign(counters, to: counters.updating(worker, to: Expr<Int>(
                            StateExpr.operatorApplication(
                                .lambda(FormalLambda(
                                    parameters: ["value"],
                                    body: StateExpr.variable("value") + 1
                                )),
                                [.value(counters[worker].raw)]
                            )
                        )))
                    }
                }
            }
        }
    }
}
