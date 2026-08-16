import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct ProcedureCallReturnWitness {
    public static var spec: TLASpec {
        #spec("ProcedureCallReturnWitness") {
            Algorithm("ProcedureCallReturnWitness") {
                let output = SharedVar(initial: 0)

                Procedure("addOffset", parameters: Int.self) { value in
                    let offset = LocalVar(initial: 2)
                    Do("apply") {
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                }

                Do("start") { Call("addOffset", with: 5) }
                Do("done") { Stop() }
            }
        }
    }
}
