import SwiftTLA

public struct ProcedureCallReturnWitness {
    private enum Label: String, CaseIterable {
        case apply, start, done
    }

    private enum ProcedureName: String, CaseIterable {
        case addOffset
    }

    public static var spec: TLASpec {
        TLASpec("ProcedureCallReturnWitness") {
            Algorithm("ProcedureCallReturnWitness", scoped: { scope in
                let output = scope.sharedVar("output", initial: 0)
                Procedure(ProcedureName.addOffset, parameters: Int.self, scoped: { value, scope in
                    let offset = scope.localVar("offset", initial: 2)
                    Do(Label.apply) {
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                })

                Do(Label.start) { Call(ProcedureName.addOffset, with: 5) }
                Do(Label.done) { Stop() }
            })
        }
    }
}
