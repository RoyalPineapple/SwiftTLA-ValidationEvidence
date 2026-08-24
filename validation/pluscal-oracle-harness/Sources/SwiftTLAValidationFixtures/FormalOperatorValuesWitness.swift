import SwiftTLA

public struct FormalOperatorValuesWitness {
    public enum Worker: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        public static let finiteValues = allCases
        public static var defaultValue: Self { .left }
    }

    private enum Label: String, CaseIterable {
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
