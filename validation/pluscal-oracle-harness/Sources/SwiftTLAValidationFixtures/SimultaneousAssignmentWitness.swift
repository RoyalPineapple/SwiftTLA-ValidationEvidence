import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct SimultaneousAssignmentWitness {
    public static var spec: TLASpec {
        #spec("SimultaneousAssignmentWitness") {
            Algorithm("SimultaneousAssignmentWitness") {
                let left = SharedVar(initial: 1)
                let right = SharedVar(initial: 2)

                Do("swap") {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            }
        }
    }
}
