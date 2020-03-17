module lang::minijavarepl::Interpreter

import lang::minijavarepl::AuxiliarySyntax;
import lang::minijava::Syntax;
import lang::minijavarepl::Syntax;
extend lang::minijava::Interpreter;

import lang::std::Layout;

import util::Maybe;
import IO;

Context exec(Program p) = exec(p, empty_context());
Context exec((Program) `<Phrase* phrases>`, Context c) = ( c | phrase_decl(phrase, it) | phrase <- phrases );
	
Context phrase_decl((Phrase) `<Expression E> ;`, Context c) = phrase_decl((Phrase) `System.out.println(<Expression E>);`, c);
Context phrase_decl((Phrase) `<Statement S>`, Context c) = exec(c, S);
Context phrase_decl((Phrase) `<ClassDecl CD>`, Context c) = accumulate(phrase_class(c, CD));
Context phrase_decl((Phrase) `<VarDecl VD>`, Context c) = accumulate(declare_variables(c, [VD]));
Context phrase_decl((Phrase) `<MethodDecl MD>`, Context c) = accumulate(declare_global_method(c, MD));

Context accumulate(Context c) {
  if (!c.failed && envlit(env) := get_result(c)) {
    return env_override(c, env);
  }
  else return set_fail(c);
}

Context phrase_class(Context c, ClassDecl CD) {
  c = bind_class_occurrences_(c, class_occurrences(CD));
  if (!c.failed && envlit(env) := get_result(c)) {
    return redeclare_class(env_override(c, env), CD);
  }
  else return set_fail(c);
}

Context redeclare_class(Context c, (ClassDecl) 
  `class <Identifier ID1> extends <Identifier ID2> { <VarDecl* VDs> <MethodDecl* MDs> }`) 
  = redeclare_class(c, ID1, VDs, MDs, just("<ID2>"));
Context redeclare_class(Context c, (ClassDecl) 
  `class <Identifier ID1> { <VarDecl* VDs> <MethodDecl* MDs> }`) 
  = redeclare_class(c, ID1, VDs, MDs, nothing());
Context redeclare_class(Context c, ID, VDs, MDs, Maybe[str] mID2) {
  c = declare_class_val(c, ID, VDs, MDs, mID2);
  if (!c.failed && classlit(class_val) := get_result(c)) {
    try {
	    if(ref(r) := c.env["<ID>"]) {
	  	  if (classlit(old_class) := c.sto[r]) {
	  	    return set_result(sto_override(c, ( r : classlit(class_override(class_val,old_class)) )), envlit(( "<ID>" : ref(r))));
	  	  }
	  	  else {
	  	    return set_result(sto_override(c, ( r : classlit(class_val) )), envlit(( "<ID>" : ref(r))));
	  	  }  
	    }
	    else return set_fail(c);
	}    
	catch exc: {print(exc); return set_fail(c);}
  }
  else return set_fail(c);
}

Context bind_class_occurrences_(Context c, class_names) { // alternative method name to ensure it is called
  Env res = ();
  for (class_name <- class_names) {
    if ("<class_name>" in c.env) {
      res = res + ("<class_name>" : c.env["<class_name>"]);
    } else {
      <r, c> = fresh_atom(c);
      c = sto_override(c, ( r : null_value() ));
      res = res + ("<class_name>" : ref(r));
    }
  }
  return set_result(c, envlit(res));
}

Context declare_global_method(Context c0, (MethodDecl) 
	`public <Type T> <Identifier ID> ( <FormalList? FLs> ) { 
	'  <VarDecl* VDs> <Statement* Ss> return <Expression E> ;
	'}`) {
    <r, c0> = fresh_atom(c0); // required for recursion
	clos = closure(Context(Context local_c) {
	  return in_environment(local_c, c0.env, Context(Context local_c) {
	    if (listlit([*ARGS]) := get_given(local_c)) {
	      local_c = match_formals(local_c, formal_list(FLs), ARGS);
          if(!local_c.failed && envlit(args_map) := get_result(local_c)) {
	        local_c = declare_variables(local_c, [VD | VD <- VDs]);	
		    if (!local_c.failed && envlit(local_map) := get_result(local_c)) {
		      return in_environment(local_c, ("<ID>" : ref(r)) + args_map + local_map, Context(Context local_c) {
		        return eval(exec(local_c, [ s | s <- Ss] ), E);
		      });
		    }
	        else return set_fail(local_c);
          }
          else return set_fail(local_c);
	    }
	    else return set_fail(local_c);
	  });
	});
    c0 = sto_override(c0, (r : clos));
	return set_result(c0, envlit( ("<ID>":ref(r)) ));
}

Context eval(Context c0, (Expression) `<Identifier ID> ( <ExpressionList? ELs> )`) {
 c = c0;
 try {
   if(ref(r) := c.env["<ID>"] && closure(clos) := c.sto[r]) {
       c = evaluate_actuals(c, actuals(ELs));
       if(!c.failed && listlit(ARGS) := get_result(c)) {
         return with_given(c, listlit(ARGS), clos);
       }
       else return set_fail(c);
    }
    else return set_fail(c);
  }
  catch: {
    return eval(c0, (Expression) `this.<Identifier ID> ( <ExpressionList? ELs> )`);
  }
}