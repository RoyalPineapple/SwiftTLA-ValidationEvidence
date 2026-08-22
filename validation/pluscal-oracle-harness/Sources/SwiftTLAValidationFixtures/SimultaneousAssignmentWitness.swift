import SwiftTLA

public struct SimultaneousAssignmentWitness {
    private enum Label: String, PlusCalLabel, CaseIterable {
        case swap
    }

    public static var spec: TLASpec {
        TLASpec("SimultaneousAssignmentWitness") {
            Algorithm("SimultaneousAssignmentWitness") {
                let left = SharedVar("left", initial: 1)
                left
                let right = SharedVar("right", initial: 2)
                right

                Do(Label.swap) {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            }
        }
    }
}
