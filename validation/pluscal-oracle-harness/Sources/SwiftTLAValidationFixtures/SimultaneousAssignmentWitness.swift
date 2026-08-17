import SwiftTLA

public struct SimultaneousAssignmentWitness {
    public static var spec: TLASpec {
        TLASpec("SimultaneousAssignmentWitness") {
            Algorithm("SimultaneousAssignmentWitness") {
                let left = SharedVar("left", initial: 1)
                left
                let right = SharedVar("right", initial: 2)
                right

                Do("swap") {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            }
        }
    }
}
