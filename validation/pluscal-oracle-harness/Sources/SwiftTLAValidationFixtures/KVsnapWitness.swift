import SwiftTLA
import SwiftTLAMacros

/// Bounded KVsnap witness from KVsnap.tla and MCKVsnap.cfg.
@TLAModel
public struct KVsnapWitness {
    public enum Key: String, FiniteDomainKey {
        case k1, k2
        public static let formalDomain: [Self] = [.k1, .k2]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.key-value-store.key")
        public var tlaValue: TLAValue { .constant(rawValue) }
        public static var defaultValue: Self { .k1 }
        public init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    public enum Transaction: String, FiniteDomainKey {
        case t1, t2, t3
        public static let formalDomain: [Self] = [.t1, .t2, .t3]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.key-value-store.transaction")
        public var tlaValue: TLAValue { .constant(rawValue) }
        public static var defaultValue: Self { .t1 }
        public init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    public enum NoValue: String, TLAValueType {
        case noVal = "NoVal"
        public var tlaValue: TLAValue { .constant(rawValue) }
        public static var defaultValue: Self { .noVal }
        public init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    public enum OperationKind: String, TLAValueType { case read, write }
    public typealias Value = OneOf<Transaction, NoValue>

    public struct OperationFields {
        public let operation: OperationKind
        public let key: Key
        public let value: Value
    }

    public enum OperationSchema: TLARecordSchema {
        public typealias Fields = OperationFields
        public static let fieldNames: Set<String> = ["op", "key", "value"]
        public static let defaultRecord: TLAValue = .record([
            "op": OperationKind.read.tlaValue,
            "key": Key.k1.tlaValue,
            "value": Value.second(.noVal).tlaValue,
        ])
        public static func fieldName<Value>(for field: KeyPath<OperationFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \OperationFields.operation { return "op" }
            if key == \OperationFields.key { return "key" }
            if key == \OperationFields.value { return "value" }
            return nil
        }
        public static let operation = field(\OperationFields.operation)
        public static let key = field(\OperationFields.key)
        public static let value = field(\OperationFields.value)
    }

    private enum Step: String, PlusCalLabel { case start = "START", read = "READ", update = "UPDATE", commit = "COMMIT" }

    public static var spec: TLASpec {
        #spec("KVsnap") {
            Extends("Integers, Sequences, FiniteSets")
            Import(KeyValueStoreUtil.module)
            let keys = SetExpr<Key>.literal(.k1, .k2)
            let values = SetExpr<Value>.literal(.first(.t1), .first(.t2), .first(.t3), .second(.noVal))
            Instance("CC", of: ClientCentric.module, with: [
                ModuleArgument("Keys", value: keys), ModuleArgument("Values", value: values),
            ])
            FormalDefinition("InitialState", body: Function<Key, Value>.mapping { _ in .second(.noVal) }.raw)
            FormalDefinition("SetToSeq", parameters: [.value("S")], body: .choose(
                .functionSet(.integerRange(.int(1), .cardinality(.variable("S"))), .variable("S")), "f",
                .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
            ))

            Algorithm("KVsnap") {
                let store = SharedVar(initial: FormalCall<Function<Key, Value>>("InitialState"))
                let tx = SharedVar(initial: SetExpr<Transaction>())
                let missed = SharedVar(initial: Function<Transaction, SetExpr<Key>>.mapping { _ in SetExpr<Key>() })
                Each(Transaction.all, fairness: .weak) { selfID in
                    let snapshotStore: LocalVariable<Function<Key, Value>> = LocalVar(initial: FormalCall<Function<Key, Value>>("InitialState"))
                    let readKeys: LocalVariable<SetExpr<Key>> = LocalVar(initial: SetExpr<Key>())
                    let writeKeys: LocalVariable<SetExpr<Key>> = LocalVar(initial: SetExpr<Key>())
                    let ops: LocalVariable<TupleExpr<Record<OperationSchema>>> = LocalVar(initial: TupleExpr<Record<OperationSchema>>())
                    Do(Step.start) {
                        Assign(tx, to: tx.inserting(selfID)); Assign(snapshotStore, to: store)
                        With(NonEmptySubsets(of: keys)) { reads in
                            With(NonEmptySubsets(of: keys)) { writes in
                                Assign(readKeys, to: reads.expr); Assign(writeKeys, to: writes.expr)
                            }
                        }
                    }
                    Do(Step.read) {
                        let reads = readKeys.expr.mapping { key in ModuleCall<Record<OperationSchema>>("CC", "r", key.expr, snapshotStore[key]) }
                        Assign(ops, to: ops.expr.concatenating(FormalCall("SetToSeq", reads)))
                    }
                    Do(Step.update) {
                        Assign(snapshotStore, to: Function<Key, Value>.mapping { key in
                            If(writeKeys.expr.contains(key), then: Value.first(selfID.expr), else: snapshotStore[key])
                        })
                    }
                    Do(Step.commit) {
                        If(missed[selfID].intersection(writeKeys.expr).isEmpty) {
                            Let(tx.removing(selfID)) { committedTransactions in
                                Assign(tx, to: committedTransactions.expr)
                                Assign(missed, to: Function<Transaction, SetExpr<Key>>.mapping { other in
                                    If(committedTransactions.expr.contains(other), then: missed[other].union(writeKeys.expr), else: missed[other])
                                })
                                Assign(store, to: Function<Key, Value>.mapping { key in
                                    If(writeKeys.expr.contains(key), then: snapshotStore[key], else: store[key])
                                })
                                let writes = writeKeys.expr.mapping { key in ModuleCall<Record<OperationSchema>>("CC", "w", key.expr, Value.first(selfID.expr)) }
                                Assign(ops, to: ops.expr.concatenating(FormalCall("SetToSeq", writes)))
                            }
                        }
                    }
                    Invariant("SnapshotIsolation") {
                        ModuleCall<Bool>("CC", "SnapshotIsolation", FormalCall<Function<Key, Value>>("InitialState"), ops.family(for: Transaction.self).range).raw
                    }
                }
                Invariant("TypeOK") {
                    Functions(from: Key.all, to: values).contains(store.expr)
                        && tx.isSubset(of: SetExpr<Transaction>.literal(.t1, .t2, .t3))
                        && Functions(from: Transaction.all, to: Subsets(of: keys)).contains(missed.expr)
                }
                Eventually("Termination", All(Transaction.all) { Finished($0) })
            }
        }
    }
}
