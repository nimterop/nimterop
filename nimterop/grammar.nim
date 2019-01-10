import strformat, strutils, tables

import regex

import treesitter/runtime

import "."/[getters, globals, lisp]

proc initGrammar() =
  # #define X Y
  gStateRT.grammar.add(("""
   (preproc_def
    (identifier)
    (preproc_arg)
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      let
        name = gStateRT.data[0].val.getIdentifier()
        val = gStateRT.data[1].val.getLit()

      if name notin gStateRT.consts and val.nBl:
        gStateRT.consts.add(name)
        gStateRT.constStr &= &"  {name}* = {val}\n"
  ))

  let typeGrammar = """
    (type_qualifier?)
    (primitive_type|type_identifier?)
    (sized_type_specifier?
     (primitive_type?)
    )
    (struct_specifier|union_specifier|enum_specifier?
     (type_identifier)
    )
  """

  # typedef int X
  # typedef X Y
  # typedef struct X Y
  # typedef ?* Y
  gStateRT.grammar.add((&"""
   (type_definition
    {typeGrammar}
    (type_identifier?)
    (pointer_declarator?
     (type_identifier)
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      var
        name = gStateRT.data[1].val.getIdentifier()
        typ = gStateRT.data[0].val.getIdentifier()

      if name notin gStateRT.types:
        gStateRT.types.add(name)
        if name == typ:
          typ = "object"
        gStateRT.typeStr &= &"  {name}* = {typ}\n"
  ))

  template funcParamCommon(pname, ptyp, pout, count, i: untyped): untyped =
    ptyp = gStateRT.data[i].val.getIdentifier()
    if i+1 < gStateRT.data.len and gStateRT.data[i+1].name == "identifier":
      pname = gStateRT.data[i+1].val.getIdentifier()
      i += 2
    else:
      pname = "a" & $count
      count += 1
      i += 1
    if ptyp != "object":
      pout &= &"{pname}: {ptyp},"

  proc pStructCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int) =
    var
      nname = name.getIdentifier()
      prefix = ""
      union = ""

    case $node.tsNodeType():
      of "struct_specifier":
        prefix = "struct "
      of "union_specifier":
        prefix = "union "
        union = " {.union.}"
      of "type_definition":
        if node.getTSNodeNamedChildCountSansComments() != 0:
          for i in 0 .. node.tsNodeNamedChildCount()-1:
            let
              nchild = $node.tsNodeNamedChild(i).tsNodeType()
            if nchild != "comment":
              if nchild == "union_specifier":
                union = " {.union.}"
              break

    if nname notin gStateRT.types:
      gStateRT.types.add(nname)
      gStateRT.typeStr &= &"  {nname}* {{.importc: \"{prefix}{name}\", header: {gStateRT.currentHeader}, bycopy.}} = object{union}\n"

      var
        i = fstart
      while i < gStateRT.data.len-fend:
        if gStateRT.data[i].name == "field_declaration":
          i += 1
          continue

        let
          ftyp = gStateRT.data[i].val.getIdentifier()
          fname = gStateRT.data[i+1].val.getIdentifier()
        if i+2 < gStateRT.data.len-fend and gStateRT.data[i+2].name in ["identifier", "number_literal"]:
          let
            flen = gStateRT.data[i+2].val.getIdentifier()
          gStateRT.typeStr &= &"    {fname}*: array[{flen}, {ftyp}]\n"
          i += 3
        elif i+2 < gStateRT.data.len-fend and gStateRT.data[i+2].name == "function_declarator":
          var
            pout, pname, ptyp = ""
            count = 1

          i += 3
          while i < gStateRT.data.len-fend:
            if gStateRT.data[i].name == "function_declarator":
              i += 1
              continue

            if gStateRT.data[i].name == "field_declaration":
              break

            funcParamCommon(pname, ptyp, pout, count, i)

          if pout.len != 0 and pout[^1] == ',':
            pout = pout[0 .. ^2]
          if ftyp != "object":
            gStateRT.typeStr &= &"    {fname}*: proc({pout}): {ftyp} {{.nimcall.}}\n"
          else:
            gStateRT.typeStr &= &"    {fname}*: proc({pout}) {{.nimcall.}}\n"
          i += 1
        else:
          gStateRT.typeStr &= &"    {fname}*: {ftyp}\n"
          i += 2

  let
    paramListGrammar = &"""
     (parameter_list
      (parameter_declaration*
       {typeGrammar}
       (identifier?)
       (pointer_declarator?
        (identifier)
       )
       (abstract_pointer_declarator?)
      )
     )
    """

    fieldGrammar = &"""
      (field_identifier?)
      (array_declarator?
       (field_identifier)
       (identifier|number_literal)
      )
      (function_declarator?
       (pointer_declarator
        (field_identifier)
       )
       {paramListGrammar}
      )
    """

    fieldListGrammar = &"""
      (field_declaration_list
       (field_declaration+
        {typeGrammar}
        {fieldGrammar}
        (pointer_declarator?
         {fieldGrammar}
        )
       )
      )
    """

  # struct X {}
  gStateRT.grammar.add((&"""
   (struct_specifier|union_specifier
    (type_identifier)
    {fieldListGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      pStructCommon(ast, node, gStateRT.data[0].val, 1, 1)
  ))

  # typedef struct X {}
  gStateRT.grammar.add((&"""
   (type_definition
    (struct_specifier|union_specifier
     (type_identifier?)
     {fieldListGrammar}
    )
    (type_identifier)
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      var
        offset = 0

      if gStateRT.data[0].name == "type_identifier":
        offset = 1

      pStructCommon(ast, node, gStateRT.data[^1].val, offset, 1)
  ))

  proc pEnumCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int) =
    var
      nname = name.getIdentifier()

    if nname.len == 0:
      nname = getUniqueIdentifier(gStateRT.enums, "Enum")

    if nname notin gStateRT.enums:
      gStateRT.enums.add(nname)
      gStateRT.enumStr &= &"\ntype {nname}* = distinct int"
      gStateRT.enumStr &= &"\nconverter enumToInt(en: {nname}): int {{.used.}} = en.int\n"

      var
        i = fstart
        count = 0
      while i < gStateRT.data.len-fend:
        let
          fname = gStateRT.data[i].val.getIdentifier()

        if fname notin gStateRT.consts:
          if i+1 < gStateRT.data.len-fend and gStateRT.data[i+1].name in ["math_expression", "number_literal"]:
            gStateRT.constStr &= &"  {fname}* = {gStateRT.data[i+1].val}.{nname}\n"
            try:
              count = gStateRT.data[i+1].val.parseInt() + 1
            except:
              count += 1
            i += 2
          else:
            gStateRT.constStr &= &"  {fname}* = {count}.{nname}\n"
            i += 1
            count += 1

  # enum X {}
  gStateRT.grammar.add(("""
   (enum_specifier
    (type_identifier?)
    (enumerator_list
     (enumerator+
      (identifier)
      (number_literal?)
      (math_expression?
       (number_literal)
      )
     )
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      var
        name = ""
        offset = 0

      if gStateRT.data[0].name == "type_identifier":
        name = gStateRT.data[0].val
        offset = 1

      pEnumCommon(ast, node, name, offset, 0)
  ))

  # typedef enum {} X
  gStateRT.grammar.add((&"""
   (type_definition
    {gStateRT.grammar[^1].grammar}
    (type_identifier)
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      var
        offset = 0

      if gStateRT.data[0].name == "type_identifier":
        offset = 1

      pEnumCommon(ast, node, gStateRT.data[^1].val, offset, 1)
  ))

  let funcGrammar = &"""
    (function_declarator*
     (identifier)
     {paramListGrammar}
    )
  """

  # typ function(typ param1, ...)
  gStateRT.grammar.add((&"""
   (declaration
    (storage_class_specifier?)
    {typeGrammar}
    {funcGrammar}
    (pointer_declarator*
     {funcGrammar}
    )
    {funcGrammar}
    (pointer_declarator*
     {funcGrammar}
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      let
        ftyp = gStateRT.data[0].val.getIdentifier()

      var
        i = 1
      while i < gStateRT.data.len:
        if gStateRT.data[i].name == "function_declarator":
          i += 1
          continue

        var
          fname = gStateRT.data[i].val
          fnname = fname.getIdentifier()
          pout, pname, ptyp = ""
          count = 1

        i += 1
        while i < gStateRT.data.len:
          if gStateRT.data[i].name == "function_declarator":
            break

          funcParamCommon(pname, ptyp, pout, count, i)

        if pout.len != 0 and pout[^1] == ',':
          pout = pout[0 .. ^2]

        if fnname notin gStateRT.procs:
          gStateRT.procs.add(fnname)
          if ftyp != "object":
            gStateRT.procStr &= &"proc {fnname}*({pout}): {ftyp} {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"
          else:
            gStateRT.procStr &= &"proc {fnname}*({pout}) {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"

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
    for n in ast.name.split("|"):
      if n notin gStateRT.ast:
        gStateRT.ast[n] = @[ast]
      else:
        gStateRT.ast[n].add(ast)

proc printGrammar*() =
  for name in gStateRT.ast.keys():
    for ast in gStateRT.ast[name]:
      echo ast.printAst()
