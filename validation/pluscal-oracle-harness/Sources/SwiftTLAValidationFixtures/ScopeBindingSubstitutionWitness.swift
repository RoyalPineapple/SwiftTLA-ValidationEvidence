import SwiftTLA

public struct ScopeBindingSubstitutionWitness {
    public static var spec: TLASpec {
        TLASpec("ScopeBindingSubstitutionWitness") {
            Algorithm("ScopeBindingSubstitutionWitness") {
                let total = SharedVar("total", initial: 0)
                total
                let commit = Macro { (destination: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(destination, to: value.expr)
                }

                Do("bind") {
                    Let(1) { base in
                        With(SetExpr<Int>.literal(2)) { selected in
                            Choose(3...3) { chosen in
                                commit(total, base.expr + selected.expr + chosen.expr)
                            }
                        }
                    }
                }
            }
        }
    }
}
