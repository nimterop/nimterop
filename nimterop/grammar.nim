import macros, strformat, strutils, tables

import regex

import "."/[getters, globals, lisp, treesitter/api]

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
      if nimState.gState.debug:
        nimState.debugStr &= "\n# define X Y"

      let
        val = nimState.data[1].val.getLit()

      if val.nBl:
        let
          name = nimState.getIdentifier(nimState.data[0].val, nskConst)

        if name.nBl and nimState.addNewIdentifer(name):
          nimState.constStr &= &"{nimState.getComments()}\n  {name}* = {val}"
  ))

  let
    typeGrammar = """
     (type_qualifier?)
     (primitive_type|type_identifier?)
     (type_qualifier?)
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
        (type_qualifier?)
        (pointer_declarator!
         (type_qualifier?)
         (identifier|type_identifier)
        )
        (identifier|type_identifier)
       )
       (abstract_pointer_declarator?
        (abstract_pointer_declarator?)
       )
      )
     )
    """

    funcGrammar = &"""
     (function_declarator*
      (identifier|type_identifier!)
      (pointer_declarator
       (pointer_declarator!
        (type_identifier)
       )
       (type_identifier)
      )
      {paramListGrammar}
      (noexcept|throw_specifier?)
     )
    """

    arrGrammar = &"""
     (array_declarator!
      (pointer_declarator!
       (pointer_declarator!
        (type_identifier)
       )
       (type_identifier)
      )
      (type_identifier)
      (identifier|number_literal)
     )
    """

  template funcParamCommon(fname, pname, ptyp, pptr, pout, count, i: untyped): untyped =
    ptyp = nimState.getIdentifier(nimState.data[i].val, nskType, fname).getType()

    pptr = ""
    while i+1 < nimState.data.len and nimState.data[i+1].name == "pointer_declarator":
      pptr &= "ptr "
      i += 1

    if i+1 < nimState.data.len and nimState.data[i+1].name == "identifier":
      pname = nimState.getIdentifier(nimState.data[i+1].val, nskParam, fname)
      i += 2
    else:
      pname = "a" & $count
      count += 1
      i += 1

    if pptr.len != 0 or ptyp != "object":
      pout &= &"{pname}: {getPtrType(pptr&ptyp)}, "

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
     (pointer_declarator!
      (type_identifier!)
      {arrGrammar}
      {funcGrammar}
     )
     (type_identifier!)
     {arrGrammar}
     {funcGrammar}
    )
    {funcGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      if nimState.gState.debug:
        nimState.debugStr &= "\n# typedef X Y"

      var
        i = 0
        typ = nimState.getIdentifier(nimState.data[i].val, nskType).getType()
        name = ""
        nname = ""
        tptr = ""
        aptr = ""

      i += 1
      while i < nimState.data.len and "pointer" in nimState.data[i].name:
        case nimState.data[i].name:
          of "pointer_declarator":
            tptr &= "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr &= "ptr "
            i += 1

      if i < nimState.data.len:
        name = nimState.data[i].val
        nname = nimState.getIdentifier(name, nskType)
        i += 1

      let
        pragma = nimState.getPragma(nimState.getImportC(name, nname))

      if nname notin gTypeMap and typ.nBl and nname.nBl and nimState.addNewIdentifer(nname):
        if i < nimState.data.len and nimState.data[^1].name == "function_declarator":
          var
            fname = nname
            pout, pname, ptyp, pptr = ""
            count = 1

          while i < nimState.data.len:
            if nimState.data[i].name == "function_declarator":
              break

            funcParamCommon(fname, pname, ptyp, pptr, pout, count, i)

          if pout.len != 0 and pout[^2 .. ^1] == ", ":
            pout = pout[0 .. ^3]

          if tptr.len != 0 or typ != "object":
            nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = proc({pout}): {getPtrType(tptr&typ)} {{.cdecl.}}"
          else:
            nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = proc({pout}) {{.cdecl.}}"
        else:
          if i < nimState.data.len and nimState.data[i].name in ["identifier", "number_literal"]:
            var
              flen = nimState.data[i].val
            if nimState.data[i].name == "identifier":
              flen = nimState.getIdentifier(flen, nskConst, nname)

            nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = {aptr}array[{flen}, {getPtrType(tptr&typ)}]"
          else:
            if nname == typ:
              nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = object"
            else:
              nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = {getPtrType(tptr&typ)}"
  ))

  proc pDupTypeCommon(nname: string, fend: int, nimState: NimState, isEnum=false) =
    if nimState.gState.debug:
      nimState.debugStr &= "\n#   pDupTypeCommon()"

    var
      dname = nimState.data[^1].val
      ndname = nimState.getIdentifier(dname, nskType)
      dptr =
        if fend == 2:
          "ptr "
        else:
          ""

    if ndname.nBl and ndname != nname:
      if isEnum:
        if nimState.addNewIdentifer(ndname):
          nimState.enumStr &= &"{nimState.getComments(true)}\ntype {ndname}* = {dptr}{nname}"
      else:
        if nimState.addNewIdentifer(ndname):
          let
            pragma = nimState.getPragma(nimState.getImportc(dname, ndname), "bycopy")
          nimState.typeStr &=
            &"{nimState.getComments()}\n  {ndname}*{pragma} = {dptr}{nname}"

  proc pStructCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, nimState: NimState) =
    if nimState.gState.debug:
      nimState.debugStr &= "\n#   pStructCommon"

    var
      nname = nimState.getIdentifier(name, nskType)
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

    if nname.nBl and nimState.addNewIdentifer(nname):
      if nimState.data.len == 1:
        nimState.typeStr &= &"{nimState.getComments()}\n  {nname}* {{.bycopy.}} = object{union}"
      else:
        let
          pragma = nimState.getPragma(nimState.getImportC(prefix & name, nname), "bycopy")
        nimState.typeStr &= &"{nimState.getComments()}\n  {nname}*{pragma} = object{union}"

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

        while i < nimState.data.len-fend and "pointer" in nimState.data[i].name:
          case nimState.data[i].name:
            of "pointer_declarator":
              fptr &= "ptr "
              i += 1
            of "array_pointer_declarator":
              aptr &= "ptr "
              i += 1

        fname = nimState.getIdentifier(nimState.data[i].val, nskField, nname)

        if i+1 < nimState.data.len-fend and nimState.data[i+1].name in gEnumVals:
          let
            flen = nimState.data[i+1].val.getNimExpression()
          nimState.typeStr &= &"{nimState.getComments()}\n    {fname}*: {aptr}array[{flen}, {getPtrType(fptr&ftyp)}]"
          i += 2
        elif i+1 < nimState.data.len-fend and nimState.data[i+1].name == "bitfield_clause":
          let
            size = nimState.data[i+1].val
          nimState.typeStr &= &"{nimState.getComments()}\n    {fname}* {{.bitsize: {size}.}} : {getPtrType(fptr&ftyp)} "
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

          if pout.len != 0 and pout[^2 .. ^1] == ", ":
            pout = pout[0 .. ^3]
          if fptr.len != 0 or ftyp != "object":
            nimState.typeStr &= &"{nimState.getComments()}\n    {fname}*: proc({pout}): {getPtrType(fptr&ftyp)} {{.cdecl.}}"
          else:
            nimState.typeStr &= &"{nimState.getComments()}\n    {fname}*: proc({pout}) {{.cdecl.}}"
            i += 1
        else:
          if ftyp == "object":
            nimState.typeStr &= &"{nimState.getComments()}\n    {fname}*: pointer"
          else:
            nimState.typeStr &= &"{nimState.getComments()}\n    {fname}*: {getPtrType(fptr&ftyp)}"
          i += 1

      if node.tsNodeType() == "type_definition" and
        nimState.data[^1].name == "type_identifier" and nimState.data[^1].val.len != 0:
          pDupTypeCommon(nname, fend, nimState, false)

  let
    fieldGrammar = &"""
      (field_identifier!)
      (bitfield_clause!
       (number_literal)
      )
      (array_declarator!
       (field_identifier!)
       (pointer_declarator
        (pointer_declarator!
         (field_identifier)
        )
        (field_identifier)
       )
       (^$1+)
      )
      (function_declarator+
       (pointer_declarator
        (pointer_declarator!
         (field_identifier)
        )
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
         (pointer_declarator!
          {fieldGrammar}
         )
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
      if nimState.gState.debug:
        nimState.debugStr &= "\n# struct X {}"

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
     (pointer_declarator!
      (type_identifier)
     )
     (type_identifier)
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      if nimState.gState.debug:
        nimState.debugStr &= "\n# typedef struct X {}"

      var
        fstart = 0
        fend = 1

      if nimState.data[^2].name == "pointer_declarator":
        fend = 2

      if nimState.data.len > 1 and
        nimState.data[0].name == "type_identifier" and
        nimState.data[1].name notin ["field_identifier", "pointer_declarator"]:

        fstart = 1
        pStructCommon(ast, node, nimState.data[0].val, fstart, fend, nimState)
      else:
        pStructCommon(ast, node, nimState.data[^1].val, fstart, fend, nimState)
  ))

  proc pEnumCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, nimState: NimState) =
    if nimState.gState.debug:
      nimState.debugStr &= "\n#   pEnumCommon()"

    let nname =
      if name.len == 0:
        getUniqueIdentifier(nimState, "Enum")
      else:
        nimState.getIdentifier(name, nskType)

    if nname.nBl and nimState.addNewIdentifer(nname):
      nimState.enumStr &= &"{nimState.getComments(true)}\ndefineEnum({nname})"

      var
        i = fstart
        count = 0
      while i < nimState.data.len-fend:
        if nimState.data[i].name == "enumerator":
          i += 1
          continue

        let
          fname = nimState.getIdentifier(nimState.data[i].val, nskEnumField)

        if i+1 < nimState.data.len-fend and
          nimState.data[i+1].name in gEnumVals:
          if fname.nBl and nimState.addNewIdentifer(fname):
            nimState.constStr &= &"{nimState.getComments()}\n  {fname}* = ({nimState.data[i+1].val.getNimExpression()}).{nname}"
          try:
            count = nimState.data[i+1].val.parseInt() + 1
          except:
            count += 1
          i += 2
        else:
          if fname.nBl and nimState.addNewIdentifer(fname):
            nimState.constStr &= &"{nimState.getComments()}\n  {fname}* = {count}.{nname}"
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
      if nimState.gState.debug:
        nimState.debugStr &= "\n# enum X {}"

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
     (pointer_declarator!
      (type_identifier)
     )
     (type_identifier)
    )
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      if nimState.gState.debug:
        nimState.debugStr &= "\n# typedef enum {}"

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
     (pointer_declarator!
      {funcGrammar}
     )
     {funcGrammar}
    )
    {funcGrammar}
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      if nimState.gState.debug:
        nimState.debugStr &= "\n# typ function"

      var
        fptr = ""
        i = 1

      while i < nimState.data.len:
        if nimState.data[i].name == "function_declarator":
          i += 1
          continue

        fptr = ""
        while i < nimState.data.len and nimState.data[i].name == "pointer_declarator":
          fptr &= "ptr "
          i += 1

        var
          fname = nimState.data[i].val
          fnname = nimState.getIdentifier(fname, nskProc)
          pout, pname, ptyp, pptr = ""
          count = 1

        i += 1
        while i < nimState.data.len:
          if nimState.data[i].name == "function_declarator":
            break

          funcParamCommon(fnname, pname, ptyp, pptr, pout, count, i)

        if pout.len != 0 and pout[^2 .. ^1] == ", ":
          pout = pout[0 .. ^3]

        if fnname.nBl and nimState.addNewIdentifer(fnname):
          let
            ftyp = nimState.getIdentifier(nimState.data[0].val, nskType, fnname).getType()
            pragma = nimState.getPragma(nimState.getImportC(fname, fnname), "cdecl")

          if fptr.len != 0 or ftyp != "object":
            nimState.procStr &= &"{nimState.getComments(true)}\nproc {fnname}*({pout}): {getPtrType(fptr&ftyp)}{pragma}"
          else:
            nimState.procStr &= &"{nimState.getComments(true)}\nproc {fnname}*({pout}){pragma}"
  ))

  # // comment
  result.add((&"""
   (comment
   )
  """,
    proc (ast: ref Ast, node: TSNode, nimState: NimState) =
      let
        cmt = $nimState.getNodeVal(node)

      for line in cmt.splitLines():
        let
          line = line.multiReplace([("//", ""), ("/*", ""), ("*/", "")])

        nimState.commentStr &= &"\n  # {line.strip(leading=false)}"
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
