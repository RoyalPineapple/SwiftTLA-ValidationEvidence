import SwiftTLA

public struct StructuredRecordFunctionsWitness {
    public enum Car: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        public static let finiteValues = allCases
        public static var defaultValue: Self { .left }
    }

    private enum Label: String, CaseIterable {
        case openDoor
    }

    public struct DoorFields {
        public let open: Bool
    }

    public enum Door: TLARecordSchema {
        public typealias Fields = DoorFields

        public static func fieldName<Value>(for field: KeyPath<DoorFields, Value>) -> String? {
            field as AnyKeyPath == \DoorFields.open ? "open" : nil
        }

        public static let open = field(\DoorFields.open)
        public static let fields = [TLARecordFieldDeclaration(open, default: false)]
    }

    public static var spec: TLASpec {
        TLASpec("StructuredRecordFunctionsWitness") {
            Algorithm("StructuredRecordFunctionsWitness") {
                let doors = SharedVar("doors", initial: Function<Car, Record<Door>>.literal(
                    (.left, Record<Door>.literal(.init(Door.open, false))),
                    (.right, Record<Door>.literal(.init(Door.open, false)))
                ))
                doors

                Each(Car.all) { car in
                    Do(Label.openDoor) {
                        When(doors[car][Door.open] == false)
                        Assign(doors, to: doors.updating(car) { door in
                            door.updating(Door.open, to: true)
                        })
                    }
                }
            }
        }
    }
}
