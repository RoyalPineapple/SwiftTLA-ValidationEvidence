import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct K1ScopeBindingSubstitutionWitness {
    public static var spec: TLASpec {
        #spec("K1ScopeBindingSubstitutionTLCWitness") {
            Algorithm("K1ScopeBindingSubstitutionTLCWitness") {
                let total = SharedVar(initial: 0)
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
