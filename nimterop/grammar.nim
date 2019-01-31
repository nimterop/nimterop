import macros, sets, strformat, strutils, tables

import regex

import "."/[getters, globals, lisp, treesitter/runtime]

type
  Grammar = seq[tuple[grammar: string, call: proc(ast: ref Ast, node: TSNode, nimState: NimState) {.nimcall.}]]

proc initGrammar(): Grammar =
  # #define X Y
  result.add(("""
   (preproc_def
    (identifier)
    (preproc_arg)
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      let
        val = nimState.data[1].val.getLit()

      if val.nBl:
        let
          name = nimState.data[0].val.getIdentifier(nskConst)

        if name.nBl and nimState.identifiers.addNewIdentifer(name):
          nimState.constStr &= &"\n  {name}* = {val}"
  ))

  let
    typeGrammar = """
     (type_qualifier?)
     (primitive_type|type_identifier?)
     (sized_type_specifier?
      (primitive_type?)
     )
     (struct_specifier|union_specifier|enum_specifier?
      (type_identifier)
     )
    """

    paramListGrammar = &"""
     (parameter_list
      (parameter_declaration*
       {typeGrammar}
       (identifier|type_identifier?)
       (pointer_declarator?
        (identifier|type_identifier)
       )
       (abstract_pointer_declarator?)
      )
     )
    """

    funcGrammar = &"""
     (function_declarator*
      (identifier|type_identifier!)
      (pointer_declarator
       (type_identifier)
      )
      {paramListGrammar}
     )
    """

    arrGrammar = &"""
     (array_declarator!
      (pointer_declarator!
       (type_identifier)
      )
      (type_identifier)
      (identifier|number_literal)
     )
    """

  template funcParamCommon(fname, pname, ptyp, pptr, pout, count, i: untyped): untyped =
    ptyp = nimState.data[i].val.getIdentifier(nskType, fname)

    if i+1 < nimState.data.len and nimState.data[i+1].name == "pointer_declarator":
      pptr = "ptr "
      i += 1
    else:
      pptr = ""

    if i+1 < nimState.data.len and nimState.data[i+1].name == "identifier":
      pname = nimState.data[i+1].val.getIdentifier(nskParam, fname)
      i += 2
    else:
      pname = "a" & $count
      count += 1
      i += 1

    if pptr == "ptr " or ptyp != "object":
      pout &= &"{pname}: {getPtrType(pptr&ptyp)},"

  # typedef int X
  # typedef X Y
  # typedef struct X Y
  # typedef ?* Y
  result.add((&"""
   (type_definition
    {typeGrammar}
    (type_identifier!)
    {arrGrammar}
    (pointer_declarator!
     (type_identifier!)
     {arrGrammar}
     {funcGrammar}
    )
    {funcGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      var
        i = 0
        typ = nimState.data[i].val.getIdentifier(nskType)
        name = ""
        tptr = ""
        aptr = ""

      i += 1
      if i < nimState.data.len:
        case nimState.data[i].name:
          of "pointer_declarator":
            tptr = "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr = "ptr "
            i += 1

      if i < nimState.data.len:
        name = nimState.data[i].val.getIdentifier(nskType)
        i += 1

      if typ.nBl and name.nBl and nimState.identifiers.addNewIdentifer(name):
        if i < nimState.data.len and nimState.data[^1].name == "function_declarator":
          var
            fname = name
            pout, pname, ptyp, pptr = ""
            count = 1

          while i < nimState.data.len:
            if nimState.data[i].name == "function_declarator":
              break

            funcParamCommon(fname, pname, ptyp, pptr, pout, count, i)

          if pout.len != 0 and pout[^1] == ',':
            pout = pout[0 .. ^2]

          if tptr == "ptr " or typ != "object":
            nimState.typeStr &= &"\n  {name}* = proc({pout}): {getPtrType(tptr&typ)} {{.nimcall.}}"
          else:
            nimState.typeStr &= &"\n  {name}* = proc({pout}) {{.nimcall.}}"
        else:
          if i < nimState.data.len and nimState.data[i].name in ["identifier", "number_literal"]:
            var
              flen = nimState.data[i].val
            if nimState.data[i].name == "identifier":
              flen = flen.getIdentifier(nskConst, name)

            nimState.typeStr &= &"\n  {name}* = {aptr}array[{flen}, {getPtrType(tptr&typ)}]"
          else:
            if name == typ:
              nimState.typeStr &= &"\n  {name}* = object"
            else:
              nimState.typeStr &= &"\n  {name}* = {getPtrType(tptr&typ)}"
  ))

  proc pDupTypeCommon(nname: string, fend: int, nimState: NimState, isEnum=false) =
    var
      dname = nimState.data[^1].val
      ndname = nimState.data[^1].val.getIdentifier(nskType)
      dptr =
        if fend == 2:
          "ptr "
        else:
          ""

    if ndname.nBl and ndname != nname:
      if isEnum:
        if nimState.identifiers.addNewIdentifer(ndname):
          nimState.enumStr &= &"\ntype {ndname}* = {dptr}{nname}"
      else:
        if nimState.identifiers.addNewIdentifer(ndname):
          nimState.typeStr &=
            &"\n  {ndname}* {{.importc: \"{dname}\", header: {nimState.currentHeader}, bycopy.}} = {dptr}{nname}"

  proc pStructCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, nimState: NimState) =
    var
      nname = name.getIdentifier(nskType)
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
              case nchild:
                of "struct_specifier":
                  if fstart == 1:
                    prefix = "struct "
                of "union_specifier":
                  if fstart == 1:
                    prefix = "union "
                  union = " {.union.}"
              break

    if nname.nBl and nimState.identifiers.addNewIdentifer(nname):
      if nimState.data.len == 1:
        nimState.typeStr &= &"\n  {nname}* {{.bycopy.}} = object{union}"
      else:
        nimState.typeStr &= &"\n  {nname}* {{.importc: \"{prefix}{name}\", header: {nimState.currentHeader}, bycopy.}} = object{union}"

      var
        i = fstart
        ftyp, fname: string
        fptr = ""
        aptr = ""
      while i < nimState.data.len-fend:
        fptr = ""
        aptr = ""
        if nimState.data[i].name == "field_declaration":
          i += 1
          continue

        if nimState.data[i].name notin ["field_identifier", "pointer_declarator", "array_pointer_declarator"]:
          ftyp = nimState.data[i].val.getType()
          i += 1

        case nimState.data[i].name:
          of "pointer_declarator":
            fptr = "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr = "ptr "
            i += 1

        fname = nimState.data[i].val.getIdentifier(nskField, nname)

        if i+1 < nimState.data.len-fend and nimState.data[i+1].name in gEnumVals:
          let
            flen = nimState.data[i+1].val.getNimExpression()
          nimState.typeStr &= &"\n    {fname}*: {aptr}array[{flen}, {getPtrType(fptr&ftyp)}]"
          i += 2
        elif i+1 < nimState.data.len-fend and nimState.data[i+1].name == "function_declarator":
          var
            pout, pname, ptyp, pptr = ""
            count = 1

          i += 2
          while i < nimState.data.len-fend:
            if nimState.data[i].name == "function_declarator":
              i += 1
              continue

            if nimState.data[i].name == "field_declaration":
              break

            funcParamCommon(fname, pname, ptyp, pptr, pout, count, i)

          if pout.len != 0 and pout[^1] == ',':
            pout = pout[0 .. ^2]
          if fptr == "ptr " or ftyp != "object":
            nimState.typeStr &= &"\n    {fname}*: proc({pout}): {getPtrType(fptr&ftyp)} {{.nimcall.}}"
          else:
            nimState.typeStr &= &"\n    {fname}*: proc({pout}) {{.nimcall.}}"
            i += 1
        else:
          if ftyp == "object":
            nimState.typeStr &= &"\n    {fname}*: pointer"
          else:
            nimState.typeStr &= &"\n    {fname}*: {getPtrType(fptr&ftyp)}"
          i += 1

      if node.tsNodeType() == "type_definition" and
        nimState.data[^1].name == "type_identifier" and nimState.data[^1].val.len != 0:
          pDupTypeCommon(nname, fend, nimState, false)

  let
    fieldGrammar = &"""
      (field_identifier!)
      (array_declarator!
       (field_identifier!)
       (pointer_declarator
        (field_identifier)
       )
       (^$1+)
      )
      (function_declarator+
       (pointer_declarator
        (field_identifier)
       )
       {paramListGrammar}
      )
    """ % gEnumVals.join("|")

    fieldListGrammar = &"""
      (field_declaration_list?
       (field_declaration+
        {typeGrammar}
        (pointer_declarator!
         {fieldGrammar}
        )
        {fieldGrammar}
       )
      )
    """

  # struct X {}
  result.add((&"""
   (struct_specifier|union_specifier
    (type_identifier)
    {fieldListGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      pStructCommon(ast, node, nimState.data[0].val, 1, 1, nimState)
  ))

  # typedef struct X {}
  result.add((&"""
   (type_definition
    (struct_specifier|union_specifier
     (type_identifier?)
     {fieldListGrammar}
    )
    (type_identifier!)
    (pointer_declarator
     (type_identifier)
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      var
        fstart = 0
        fend = 1

      if nimState.data[^2].name == "pointer_declarator":
        fend = 2

      if nimState.data.len > 1 and
        nimState.data[0].name == "type_identifier" and
        nimState.data[1].name != "field_identifier":

        fstart = 1
        pStructCommon(ast, node, nimState.data[0].val, fstart, fend, nimState)
      else:
        pStructCommon(ast, node, nimState.data[^1].val, fstart, fend, nimState)
  ))

  proc pEnumCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, nimState: NimState) =
    let nname =
      if name.len == 0:
        getUniqueIdentifier(nimState.identifiers, "Enum")
      else:
        name.getIdentifier(nskType)

    if nname.nBl and nimState.identifiers.addNewIdentifer(nname):
      nimState.enumStr &= &"\ndefineEnum({nname})"

      var
        i = fstart
        count = 0
      while i < nimState.data.len-fend:
        if nimState.data[i].name == "enumerator":
          i += 1
          continue

        let
          fname = nimState.data[i].val.getIdentifier(nskEnumField)

        if i+1 < nimState.data.len-fend and
          nimState.data[i+1].name in gEnumVals:
          if fname.nBl and nimState.identifiers.addNewIdentifer(fname):
            nimState.constStr &= &"\n  {fname}* = ({nimState.data[i+1].val.getNimExpression()}).{nname}"
          try:
            count = nimState.data[i+1].val.parseInt() + 1
          except:
            count += 1
          i += 2
        else:
          if fname.nBl and nimState.identifiers.addNewIdentifer(fname):
            nimState.constStr &= &"\n  {fname}* = {count}.{nname}"
          i += 1
          count += 1

      if node.tsNodeType() == "type_definition" and
        nimState.data[^1].name == "type_identifier" and nimState.data[^1].val.len != 0:
          pDupTypeCommon(nname, fend, nimState, true)

  # enum X {}
  result.add(("""
   (enum_specifier
    (type_identifier?)
    (enumerator_list
     (enumerator+
      (identifier?)
      (^$1+)
     )
    )
   )
  """ % gEnumVals.join("|"),
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      var
        name = ""
        offset = 0

      if nimState.data[0].name == "type_identifier":
        name = nimState.data[0].val
        offset = 1

      pEnumCommon(ast, node, name, offset, 0, nimState)
  ))

  # typedef enum {} X
  result.add((&"""
   (type_definition
    {result[^1].grammar}
    (type_identifier!)
    (pointer_declarator
     (type_identifier)
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      var
        fstart = 0
        fend = 1

      if nimState.data[^2].name == "pointer_declarator":
        fend = 2

      if nimState.data[0].name == "type_identifier":
        fstart = 1

        pEnumCommon(ast, node, nimState.data[0].val, fstart, fend, nimState)
      else:
        pEnumCommon(ast, node, nimState.data[^1].val, fstart, fend, nimState)
  ))

  # typ function(typ param1, ...)
  result.add((&"""
   (declaration
    (storage_class_specifier?)
    {typeGrammar}
    (pointer_declarator!
     {funcGrammar}
    )
    {funcGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      var
        fptr = ""
        i = 1

      while i < nimState.data.len:
        if nimState.data[i].name == "function_declarator":
          i += 1
          continue

        if nimState.data[i].name == "pointer_declarator":
          fptr = "ptr "
          i += 1
        else:
          fptr = ""

        var
          fname = nimState.data[i].val
          fnname = fname.getIdentifier(nskProc)
          pout, pname, ptyp, pptr = ""
          count = 1

        i += 1
        while i < nimState.data.len:
          if nimState.data[i].name == "function_declarator":
            break

          funcParamCommon(fnname, pname, ptyp, pptr, pout, count, i)

        if pout.len != 0 and pout[^1] == ',':
          pout = pout[0 .. ^2]

        if fnname.nBl and nimState.identifiers.addNewIdentifer(fnname):
          let ftyp = nimState.data[0].val.getIdentifier(nskType, fnname)

          if fptr == "ptr " or ftyp != "object":
            nimState.procStr &= &"\nproc {fnname}*({pout}): {getPtrType(fptr&ftyp)} {{.importc: \"{fname}\", header: {nimState.currentHeader}.}}"
          else:
            nimState.procStr &= &"\nproc {fnname}*({pout}) {{.importc: \"{fname}\", header: {nimState.currentHeader}.}}"

  ))

proc initRegex(ast: ref Ast) =
  if ast.children.len != 0:
    if not ast.recursive:
      for child in ast.children:
        child.initRegex()

    var
      reg: string
    try:
      reg = ast.getRegexForAstChildren()
      ast.regex = reg.re()
    except:
      echo reg
      raise newException(Exception, getCurrentExceptionMsg())

proc parseGrammar*(): AstTable =
  let grammars = initGrammar()

  result = newTable[string, seq[ref Ast]]()
  for i in 0 .. grammars.len-1:
    var
      ast = grammars[i].grammar.parseLisp()

    ast.tonim = grammars[i].call
    ast.initRegex()
    for n in ast.name.split("|"):
      if n notin result:
        result[n] = @[ast]
      else:
        result[n].add(ast)

proc printGrammar*(astTable: AstTable) =
  for name in astTable.keys():
    for ast in astTable[name]:
      echo ast.printAst()
