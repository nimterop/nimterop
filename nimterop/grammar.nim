import sets, strformat, strutils, tables

import regex

import "."/[getters, globals, lisp, treesitter/runtime]

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

      if val.nBl and gStateRT.consts.addNewIdentifer(name):
        gStateRT.constStr &= &"  {name}* = {val}\n"
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

  template funcParamCommon(pname, ptyp, pptr, pout, count, i: untyped): untyped =
    ptyp = gStateRT.data[i].val.getIdentifier()
    if i+1 < gStateRT.data.len and gStateRT.data[i+1].name == "pointer_declarator":
      pptr = "ptr "
      i += 1
    else:
      pptr = ""

    if i+1 < gStateRT.data.len and gStateRT.data[i+1].name == "identifier":
      pname = gStateRT.data[i+1].val.getIdentifier()
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
  gStateRT.grammar.add((&"""
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
    proc (ast: ref Ast, node: TSNode) =
      var
        i = 0
        typ = gStateRT.data[i].val.getIdentifier()
        name = ""
        tptr = ""
        aptr = ""

      i += 1
      if i < gStateRT.data.len:
        case gStateRT.data[i].name:
          of "pointer_declarator":
            tptr = "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr = "ptr "
            i += 1

      if i < gStateRT.data.len:
        name = gStateRT.data[i].val.getIdentifier()
        i += 1

      if gStateRT.types.addNewIdentifer(name):
        if i < gStateRT.data.len and gStateRT.data[^1].name == "function_declarator":
          var
            pout, pname, ptyp, pptr = ""
            count = 1

          while i < gStateRT.data.len:
            if gStateRT.data[i].name == "function_declarator":
              break

            funcParamCommon(pname, ptyp, pptr, pout, count, i)

          if pout.len != 0 and pout[^1] == ',':
            pout = pout[0 .. ^2]

          if tptr == "ptr " or typ != "object":
            gStateRT.typeStr &= &"  {name}* = proc({pout}): {getPtrType(tptr&typ)} {{.nimcall.}}\n"
          else:
            gStateRT.typeStr &= &"  {name}* = proc({pout}) {{.nimcall.}}\n"
        else:
          if i < gStateRT.data.len and gStateRT.data[i].name in ["identifier", "number_literal"]:
            let
              flen = gStateRT.data[i].val.getIdentifier()
            gStateRT.typeStr &= &"  {name}* = {aptr}array[{flen}, {getPtrType(tptr&typ)}]\n"
          else:
            if name == typ:
              gStateRT.typeStr &= &"  {name}* = object\n"
            else:
              gStateRT.typeStr &= &"  {name}* = {getPtrType(tptr&typ)}\n"
  ))

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
              case nchild:
                of "struct_specifier":
                  if fstart == 1:
                    prefix = "struct "
                of "union_specifier":
                  if fstart == 1:
                    prefix = "union "
                  union = " {.union.}"
              break

    if gStateRT.types.addNewIdentifer(nname):
      if gStateRT.data.len == 1:
        gStateRT.typeStr &= &"  {nname}* {{.bycopy.}} = object{union}\n"
      else:
        gStateRT.typeStr &= &"  {nname}* {{.importc: \"{prefix}{name}\", header: {gStateRT.currentHeader}, bycopy.}} = object{union}\n"

      var
        i = fstart
        ftyp, fname: string
        fptr = ""
        aptr = ""
      while i < gStateRT.data.len-fend:
        fptr = ""
        aptr = ""
        if gStateRT.data[i].name == "field_declaration":
          i += 1
          continue

        if gStateRT.data[i].name notin ["field_identifier", "pointer_declarator", "array_pointer_declarator"]:
          ftyp = gStateRT.data[i].val.getType()
          i += 1

        case gStateRT.data[i].name:
          of "pointer_declarator":
            fptr = "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr = "ptr "
            i += 1

        fname = gStateRT.data[i].val.getIdentifier()
        if i+1 < gStateRT.data.len-fend and gStateRT.data[i+1].name in gEnumVals:
          let
            flen = gStateRT.data[i+1].val.getNimExpression()
          gStateRT.typeStr &= &"    {fname}*: {aptr}array[{flen}, {getPtrType(fptr&ftyp)}]\n"
          i += 2
        elif i+1 < gStateRT.data.len-fend and gStateRT.data[i+1].name == "function_declarator":
          var
            pout, pname, ptyp, pptr = ""
            count = 1

          i += 2
          while i < gStateRT.data.len-fend:
            if gStateRT.data[i].name == "function_declarator":
              i += 1
              continue

            if gStateRT.data[i].name == "field_declaration":
              break

            funcParamCommon(pname, ptyp, pptr, pout, count, i)

          if pout.len != 0 and pout[^1] == ',':
            pout = pout[0 .. ^2]
          if fptr == "ptr " or ftyp != "object":
            gStateRT.typeStr &= &"    {fname}*: proc({pout}): {getPtrType(fptr&ftyp)} {{.nimcall.}}\n"
          else:
            gStateRT.typeStr &= &"    {fname}*: proc({pout}) {{.nimcall.}}\n"
            i += 1
        else:
          if ftyp == "object":
            gStateRT.typeStr &= &"    {fname}*: pointer\n"
          else:
            gStateRT.typeStr &= &"    {fname}*: {getPtrType(fptr&ftyp)}\n"
          i += 1

      if node.tsNodeType() == "type_definition" and
        gStateRT.data[^1].name == "type_identifier" and gStateRT.data[^1].val.len != 0:
          let
            dname = gStateRT.data[^1].val
            ndname = gStateRT.data[^1].val.getIdentifier()

          if gStateRT.types.addNewIdentifer(ndname):
            gStateRT.typeStr &= &"  {ndname}* {{.importc: \"{dname}\", header: {gStateRT.currentHeader}, bycopy.}} = {nname}\n"

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

      if gStateRT.data.len > 1 and
        gStateRT.data[0].name == "type_identifier" and
        gStateRT.data[1].name != "field_identifier":

        offset = 1
        pStructCommon(ast, node, gStateRT.data[0].val, offset, 1)
      else:
        pStructCommon(ast, node, gStateRT.data[^1].val, offset, 1)
  ))

  proc pEnumCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int) =
    var
      nname = name.getIdentifier()

    if nname.len == 0:
      nname = getUniqueIdentifier(gStateRT.enums, "Enum")

    if gStateRT.enums.addNewIdentifer(nname):
      gStateRT.enumStr &= &"\ntype {nname}* = distinct int"
      gStateRT.enumStr &= &"\nconverter enumToInt(en: {nname}): int {{.used.}} = en.int\n"

      var
        i = fstart
        count = 0
      while i < gStateRT.data.len-fend:
        let
          fname = gStateRT.data[i].val.getIdentifier()

        if gStateRT.data[i].name == "enumerator":
          i += 1
          continue

        if gStateRT.consts.addNewIdentifer(fname):
          if i+1 < gStateRT.data.len-fend and
            gStateRT.data[i+1].name in gEnumVals:
            gStateRT.constStr &= &"  {fname}* = ({gStateRT.data[i+1].val.getNimExpression()}).{nname}\n"
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
      (identifier?)
      (^$1+)
     )
    )
   )
  """ % gEnumVals.join("|"),
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

  # typ function(typ param1, ...)
  gStateRT.grammar.add((&"""
   (declaration
    (storage_class_specifier?)
    {typeGrammar}
    (pointer_declarator!
     {funcGrammar}
    )
    {funcGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode) =
      var
        ftyp = gStateRT.data[0].val.getIdentifier()
        fptr = ""
        i = 1

      while i < gStateRT.data.len:
        if gStateRT.data[i].name == "function_declarator":
          i += 1
          continue

        if gStateRT.data[i].name == "pointer_declarator":
          fptr = "ptr "
          i += 1

        var
          fname = gStateRT.data[i].val
          fnname = fname.getIdentifier()
          pout, pname, ptyp, pptr = ""
          count = 1

        i += 1
        while i < gStateRT.data.len:
          if gStateRT.data[i].name == "function_declarator":
            break

          funcParamCommon(pname, ptyp, pptr, pout, count, i)

        if pout.len != 0 and pout[^1] == ',':
          pout = pout[0 .. ^2]

        if gStateRT.procs.addNewIdentifer(fnname):
          if fptr == "ptr " or ftyp != "object":
            gStateRT.procStr &= &"proc {fnname}*({pout}): {getPtrType(fptr&ftyp)} {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"
          else:
            gStateRT.procStr &= &"proc {fnname}*({pout}) {{.importc: \"{fname}\", header: {gStateRT.currentHeader}.}}\n"

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

proc parseGrammar*() =
  gStateRT.consts.init()
  gStateRT.enums.init()
  gStateRT.procs.init()
  gStateRT.types.init()

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
