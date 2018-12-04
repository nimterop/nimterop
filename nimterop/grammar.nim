import strformat, tables

import regex

import "."/[getters, globals, lisp]

proc initGrammar() =
  # #define X Y
  gStateRT.grammar.add(("""
   (preproc_def
    (identifier)
    (preproc_arg)
   )
  """,
    proc () {.closure, locks: 0.} =
      let
        name = gStateRT.data[0].val.getIdentifier()
        val = gStateRT.data[1].val

      if name notin gStateRT.consts and val.nBl:
        gStateRT.consts.add(name)
        gStateRT.constStr &= &"  {name}* = {val}\n"
  ))

  # typedef int X
  # typedef X Y
  # typedef struct X Y
  # typedef ?* Y
  gStateRT.grammar.add(("""
   (type_definition
    (primitive_type|type_identifier?)
    (sized_type_specifier?
     (primitive_type?)
    )
    (struct_specifier?
     (type_identifier)
    )
    (type_identifier?)
    (pointer_declarator?
     (type_identifier)
    )
   )
  """,
    proc () {.closure, locks: 0.} =
      var
        name = gStateRT.data[1].val.getIdentifier()
        typ = gStateRT.data[0].val

      if name notin gStateRT.types:
        gStateRT.types.add(name)
        gStateRT.typeStr &= &"  {name}* = {typ}\n"
  ))

  proc pStructCommon(name: string, fstart, fend: int, prefix="") =
    let
      nname = name.getIdentifier()
    if nname notin gStateRT.types:
      gStateRT.types.add(nname)
      gStateRT.typeStr &= &"  {nname}* {{.importc: \"{prefix}{name}\", header: {gStateRT.currentHeader}, bycopy.}} = object\n"

      for i in fstart .. gStateRT.data.len-fend:
        let
          ftyp = gStateRT.data[i].val
          fname = gStateRT.data[i+1].val.getIdentifier()
        gStateRT.typeStr &= &"    {fname}*: {ftyp}\n"

  # struct X {}
  gStateRT.grammar.add(("""
   (struct_specifier
    (type_identifier)
    (field_declaration_list
     (field_declaration+
      (primitive_type|type_identifier?)
      (sized_type_specifier?
       (primitive_type)
      )
      (struct_specifier?
       (type_identifier)
      )
      (field_identifier?)
      (pointer_declarator?
       (field_identifier)
      )
     )
    )
   )
  """,
    proc () {.closure, locks: 0.} =
      pStructCommon(gStateRT.data[0].val, 1, 2, "struct ")
  ))

  # typedef struct X {}
  gStateRT.grammar.add(("""
   (type_definition
    (struct_specifier
     (field_declaration_list
      (field_declaration+
       (primitive_type|type_identifier?)
       (sized_type_specifier?
        (primitive_type?)
       )
       (struct_specifier?
        (type_identifier)
       )
       (field_identifier?)
       (pointer_declarator?
        (field_identifier)
       )
      )
     )
    )
    (type_identifier)
   )
  """,
    proc () {.closure, locks: 0.} =
      pStructCommon(gStateRT.data[^1].val, 0, 3)
  ))

  proc pEnumCommon(name: string, fstart, fend: int, prefix="") =
    let
      nname = name.getIdentifier()
    if nname notin gStateRT.types:
      gStateRT.types.add(nname)
      gStateRT.typeStr &= &"  {nname}* = enum\n"

      var
        i = fstart
      while i < gStateRT.data.len-fend:
        let
          fname = gStateRT.data[i].val.getIdentifier()

        if i+1 < gStateRT.data.len-fend and gStateRT.data[i+1].name == "number_literal":
          gStateRT.typeStr &= &"    {fname} = {gStateRT.data[i+1].val}\n"
          i += 2
        else:
          gStateRT.typeStr &= &"    {fname}\n"
          i += 1

  # enum X {}
  gStateRT.grammar.add(("""
   (enum_specifier
    (type_identifier)
    (enumerator_list
     (enumerator+
      (identifier)
      (number_literal?)
     )
    )
   )
  """,
    proc () {.closure, locks: 0.} =
      pEnumCommon(gStateRT.data[0].val, 1, 0)
  ))

  # typedef enum {} X
  gStateRT.grammar.add(("""
   (type_definition
    (enum_specifier
     (enumerator_list
      (enumerator+
       (identifier)
       (number_literal?)
      )
     )
    )
    (type_identifier)
   )
  """,
    proc () {.closure, locks: 0.} =
      pEnumCommon(gStateRT.data[^1].val, 0, 1)
  ))

  # typ function(typ param1, ...)
  gStateRT.grammar.add(("""
   (declaration
    (type_qualifier?)
    (primitive_type|type_identifier?)
    (sized_type_specifier?
     (primitive_type?)
    )
    (struct_specifier?
     (type_identifier)
    )
    (function_declarator?
     (identifier)
     (parameter_list
      (parameter_declaration*
       (type_qualifier?)
       (primitive_type|type_identifier?)
       (sized_type_specifier?
        (primitive_type?)
       )
       (struct_specifier?
        (type_identifier)
       )
       (enum_specifier?
        (type_identifier)
       )
       (identifier?)
       (pointer_declarator?
        (identifier)
       )
      )
     )
    )
    (pointer_declarator?
     (function_declarator
      (identifier)
      (parameter_list
       (parameter_declaration*
        (type_qualifier?)
        (primitive_type|type_identifier?)
        (sized_type_specifier?
         (primitive_type?)
        )
        (struct_specifier?
         (type_identifier)
        )
        (enum_specifier?
         (type_identifier)
        )
        (identifier?)
        (pointer_declarator?
         (identifier)
        )
       )
      )
     )
    )
   )
  """,
    proc () {.closure, locks: 0.} =
      let
        ftyp = gStateRT.data[0].val
        fname = gStateRT.data[1].val
        fnname = fname.getIdentifier()

      if fnname notin gStateRT.procs:
        var
          pout = ""
          i = 2
        if gStateRT.data.len > 2:
          while i < gStateRT.data.len-1:
            let
              ptyp = gStateRT.data[i].val
              pname = gStateRT.data[i+1].val.getIdentifier()
            pout &= &"{pname}: {ptyp},"
            i += 2
        if pout.len != 0 and pout[^1] == ',':
          pout = pout[0 .. ^2]

        if ftyp != "object":
          gStateRT.procStr &= &"proc {fnname}({pout}): {ftyp} {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"
        else:
          gStateRT.procStr &= &"proc {fnname}({pout}) {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"

  ))

proc initRegex(ast: ref Ast) =
  if ast.children.len != 0:
    for child in ast.children:
      child.initRegex()

    ast.regex = ast.getRegexForAstChildren().re()

proc parseGrammar*() =
  initGrammar()

  gStateRT.ast = initTable[string, seq[ref Ast]]()
  for i in 0 .. gStateRT.grammar.len-1:
    var
      ast = gStateRT.grammar[i].grammar.parseLisp()

    ast.tonim = gStateRT.grammar[i].call
    ast.initRegex()
    if ast.name notin gStateRT.ast:
      gStateRT.ast[ast.name] = @[ast]
    else:
      gStateRT.ast[ast.name].add(ast)

proc printGrammar*() =
  for name in gStateRT.ast.keys():
    for ast in gStateRT.ast[name]:
      echo ast.printAst()
