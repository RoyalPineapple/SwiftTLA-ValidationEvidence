import SwiftTLA

public struct ProcedureCallReturnWitness {
    public static var spec: TLASpec {
        TLASpec("ProcedureCallReturnWitness") {
            Algorithm("ProcedureCallReturnWitness") {
                let output = SharedVar("output", initial: 0)
                output

                Procedure("addOffset", parameters: Int.self) { value in
                    let offset = LocalVar("offset", initial: 2)
                    offset
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
