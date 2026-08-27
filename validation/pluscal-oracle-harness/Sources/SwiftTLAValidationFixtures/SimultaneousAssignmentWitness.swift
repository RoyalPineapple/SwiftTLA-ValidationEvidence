import SwiftTLA

public struct SimultaneousAssignmentWitness {
    private enum Label: String, CaseIterable {
        case swap
    }

    public static var spec: TLASpec {
        TLASpec("SimultaneousAssignmentWitness") {
            Algorithm("SimultaneousAssignmentWitness", scoped: { scope in
                let left = scope.sharedVar("left", initial: 1)
                let right = scope.sharedVar("right", initial: 2)

                Do(Label.swap) {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            })
        }
    }
}
