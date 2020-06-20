import macros, strformat, strutils, tables

import regex

import ".."/[globals, treesitter/api]
import "."/[ast, getters, lisp, tshelp]

type
  Grammar = seq[tuple[grammar: string, call: proc(ast: ref Ast, node: TSNode, gState: State) {.nimcall.}]]

proc getPtrType(str: string): string =
  result = case str:
    of "ptr cchar":
      "cstring"
    of "ptr ptr cchar":
      "ptr cstring"
    of "ptr object":
      "pointer"
    of "ptr ptr object":
      "ptr pointer"
    of "ptr FILE":
      "File"
    else:
      str

proc getLit(str: string): string =
  # Used to convert #define literals into const
  let
    str = str.replace(re"/[/*].*?(?:\*/)?$", "").strip()

  if str.contains(re"^[\-]?[\d]*[.]?[\d]+$") or # decimal
    str.contains(re"^0x[\da-fA-F]+$") or        # hexadecimal
    str.contains(re"^'[[:ascii:]]'$") or        # char
    str.contains(re"""^"[[:ascii:]]+"$"""):     # char *
    return str

proc initGrammar(): Grammar =
  # #define X Y
  result.add(("""
   (preproc_def
    (identifier)
    (preproc_arg)
   )
  """,
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# define X Y"

      let
        name = gState.data[0].val
        nname = gState.getIdentifier(name, nskConst)
        val = gState.data[1].val.getLit()

      if not nname.nBl:
        let
          override = gState.getOverride(name, nskConst)
        if override.nBl:
          gState.constStr &= &"{gState.getComments()}\n{override}"
        else:
          gState.constStr &= &"{gState.getComments()}\n  # Const '{name}' skipped"
          if gState.debug:
            gState.skipStr &= &"\n{gState.getNodeVal(node)}"
      elif val.nBl and gState.addNewIdentifer(nname):
        gState.constStr &= &"{gState.getComments()}\n  {nname}* = {val}"
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

    arrGrammar = &"""
     (array_declarator!
      (pointer_declarator!
       (pointer_declarator!
        (type_identifier)
       )
       (type_identifier)
      )
      (type_identifier|identifier)
      (identifier|number_literal)
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
         {arrGrammar}
         (identifier|type_identifier)
        )
        {arrGrammar}
        (identifier|type_identifier)
       )
       {arrGrammar}
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
       (type_identifier|identifier)
      )
      {paramListGrammar}
      (noexcept|throw_specifier?)
     )
    """

  template funcParamCommon(fname, pname, ptyp, pptr, pout, count, i, flen: untyped): untyped =
    ptyp = gState.getIdentifier(gState.data[i].val, nskType, fname).getType()

    pptr = ""
    while i+1 < gState.data.len and gState.data[i+1].name == "pointer_declarator":
      pptr &= "ptr "
      i += 1

    if i+1 < gState.data.len and gState.data[i+1].name == "identifier":
      pname = gState.getIdentifier(gState.data[i+1].val, nskParam, fname)
      i += 2
    else:
      pname = "a" & $count
      count += 1
      i += 1

    if i < gState.data.len and gState.data[i].name in ["identifier", "number_literal"]:
      flen = gState.data[i].val
      if gState.data[i].name == "identifier":
        flen = gState.getIdentifier(flen, nskConst, fname)

      pout &= &"{pname}: array[{flen}, {getPtrType(pptr&ptyp)}], "
      i += 1
    elif pptr.nBl or ptyp != "object":
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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# typedef X Y"

      var
        i = 0
        typ = gState.getIdentifier(gState.data[i].val, nskType, "IgnoreSkipSymbol").getType()
        name = ""
        nname = ""
        tptr = ""
        aptr = ""
        pragmas: seq[string] = @[]

      i += 1
      while i < gState.data.len and "pointer" in gState.data[i].name:
        case gState.data[i].name:
          of "pointer_declarator":
            tptr &= "ptr "
            i += 1
          of "array_pointer_declarator":
            aptr &= "ptr "
            i += 1

      if i < gState.data.len:
        name = gState.data[i].val
        nname = gState.getIdentifier(name, nskType)
        i += 1

      if not gState.noHeader and gState.dynlib.Bl:
        pragmas.add gState.getImportC(name, nname)

      let
        pragma = gState.getPragma(pragmas)

      if not nname.nBl:
        let
          override = gState.getOverride(name, nskType)
        if override.nBl:
          gState.typeStr &= &"{gState.getComments()}\n{override}"
      elif nname notin gTypeMap and typ.nBl and gState.addNewIdentifer(nname):
        if i < gState.data.len and gState.data[^1].name == "function_declarator":
          var
            fname = nname
            pout, pname, ptyp, pptr = ""
            count = 1
            flen = ""

          while i < gState.data.len:
            if gState.data[i].name == "function_declarator":
              break

            funcParamCommon(fname, pname, ptyp, pptr, pout, count, i, flen)

          if pout.nBl and pout[^2 .. ^1] == ", ":
            pout = pout[0 .. ^3]

          if tptr.nBl or typ != "object":
            gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = proc({pout}): {getPtrType(tptr&typ)} {{.cdecl.}}"
          else:
            gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = proc({pout}) {{.cdecl.}}"
        else:
          if i < gState.data.len and gState.data[i].name in ["identifier", "number_literal"]:
            var
              flen = gState.data[i].val
            if gState.data[i].name == "identifier":
              flen = gState.getIdentifier(flen, nskConst, nname)

            gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = {aptr}array[{flen}, {getPtrType(tptr&typ)}]"
          else:
            if nname == typ:
              pragmas.add "incompleteStruct"
              let
                pragma = gState.getPragma(pragmas)
              gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = object"
            else:
              gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = {getPtrType(tptr&typ)}"
  ))

  proc pDupTypeCommon(nname: string, fend: int, gState: State, isEnum=false) =
    if gState.debug:
      gState.debugStr &= "\n#   pDupTypeCommon()"

    var
      dname = gState.data[^1].val
      ndname = gState.getIdentifier(dname, nskType)
      dptr =
        if fend == 2:
          "ptr "
        else:
          ""

    if ndname.nBl and ndname != nname:
      if isEnum:
        if gState.addNewIdentifer(ndname):
          gState.enumStr &= &"{gState.getComments(true)}\ntype {ndname}* = {dptr}{nname}"
      else:
        if gState.addNewIdentifer(ndname):
          let
            pragma = gState.getPragma(gState.getImportc(dname, ndname), "bycopy")
          gState.typeStr &=
            &"{gState.getComments()}\n  {ndname}*{pragma} = {dptr}{nname}"

  proc pStructCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, gState: State) =
    if gState.debug:
      gState.debugStr &= "\n#   pStructCommon"

    var
      nname = gState.getIdentifier(name, nskType)
      prefix = ""
      union = ""

    case $node.tsNodeType():
      of "struct_specifier":
        prefix = "struct "
      of "union_specifier":
        prefix = "union "
        union = ", union"
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
                  union = ", union"
              break

    if not nname.nBl:
      let
        override = gState.getOverride(name, nskType)
      if override.nBl:
        gState.typeStr &= &"{gState.getComments()}\n{override}"
    elif gState.addNewIdentifer(nname):
      if gState.data.len == 1:
        gState.typeStr &= &"{gState.getComments()}\n  {nname}* {{.bycopy{union}.}} = object"
      else:
        var
          pragmas: seq[string] = @[]
        if not gState.noHeader and gState.dynlib.Bl:
          pragmas.add gState.getImportC(prefix & name, nname)
        pragmas.add "bycopy"
        if union.nBl:
          pragmas.add "union"

        let
          pragma = gState.getPragma(pragmas)

        gState.typeStr &= &"{gState.getComments()}\n  {nname}*{pragma} = object"

      var
        i = fstart
        ftyp, fname: string
        fptr = ""
        aptr = ""
        flen = ""
      while i < gState.data.len-fend:
        fptr = ""
        aptr = ""
        if gState.data[i].name == "field_declaration":
          i += 1
          continue

        if gState.data[i].name notin ["field_identifier", "pointer_declarator", "array_pointer_declarator"]:
          ftyp = gState.getIdentifier(gState.data[i].val, nskType, nname).getType()
          i += 1

        while i < gState.data.len-fend and "pointer" in gState.data[i].name:
          case gState.data[i].name:
            of "pointer_declarator":
              fptr &= "ptr "
              i += 1
            of "array_pointer_declarator":
              aptr &= "ptr "
              i += 1

        fname = gState.getIdentifier(gState.data[i].val, nskField, nname)

        if i+1 < gState.data.len-fend and gState.data[i+1].name in gEnumVals:
          # Struct field is an array where size is an expression
          var
            flen = gState.getNimExpression(gState.data[i+1].val)
          if "/" in flen:
            flen = &"({flen}).int"
          gState.typeStr &= &"{gState.getComments()}\n    {fname}*: {aptr}array[{flen}, {getPtrType(fptr&ftyp)}]"
          i += 2
        elif i+1 < gState.data.len-fend and gState.data[i+1].name == "bitfield_clause":
          let
            size = gState.data[i+1].val
          gState.typeStr &= &"{gState.getComments()}\n    {fname}* {{.bitsize: {size}.}} : {getPtrType(fptr&ftyp)} "
          i += 2
        elif i+1 < gState.data.len-fend and gState.data[i+1].name == "function_declarator":
          var
            pout, pname, ptyp, pptr = ""
            count = 1

          i += 2
          while i < gState.data.len-fend:
            if gState.data[i].name == "function_declarator":
              i += 1
              continue

            if gState.data[i].name == "field_declaration":
              break

            funcParamCommon(fname, pname, ptyp, pptr, pout, count, i, flen)

          if pout.nBl and pout[^2 .. ^1] == ", ":
            pout = pout[0 .. ^3]
          if fptr.nBl or ftyp != "object":
            gState.typeStr &= &"{gState.getComments()}\n    {fname}*: proc({pout}): {getPtrType(fptr&ftyp)} {{.cdecl.}}"
          else:
            gState.typeStr &= &"{gState.getComments()}\n    {fname}*: proc({pout}) {{.cdecl.}}"
            i += 1
        else:
          if ftyp == "object":
            gState.typeStr &= &"{gState.getComments()}\n    {fname}*: pointer"
          else:
            gState.typeStr &= &"{gState.getComments()}\n    {fname}*: {getPtrType(fptr&ftyp)}"
          i += 1

      if node.tsNodeType() == "type_definition" and
        gState.data[^1].name == "type_identifier" and gState.data[^1].val.nBl:
          pDupTypeCommon(nname, fend, gState, false)

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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# struct X {}"

      pStructCommon(ast, node, gState.data[0].val, 1, 1, gState)
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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# typedef struct X {}"

      var
        fstart = 0
        fend = 1

      if gState.data[^2].name == "pointer_declarator":
        fend = 2

      if gState.data.len > 1 and
        gState.data[0].name == "type_identifier" and
        gState.data[1].name notin ["field_identifier", "pointer_declarator"]:

        fstart = 1
        pStructCommon(ast, node, gState.data[0].val, fstart, fend, gState)
      else:
        pStructCommon(ast, node, gState.data[^1].val, fstart, fend, gState)
  ))

  proc pEnumCommon(ast: ref Ast, node: TSNode, name: string, fstart, fend: int, gState: State) =
    if gState.debug:
      gState.debugStr &= "\n#   pEnumCommon()"

    let nname =
      if name.Bl:
        getUniqueIdentifier(gState, "Enum")
      else:
        gState.getIdentifier(name, nskType)

    if nname.nBl and gState.addNewIdentifer(nname):
      gState.enumStr &= &"{gState.getComments(true)}\ndefineEnum({nname})"

      var
        i = fstart
        count = 0
      while i < gState.data.len-fend:
        if gState.data[i].name == "enumerator":
          i += 1
          continue

        let
          fname = gState.getIdentifier(gState.data[i].val, nskEnumField)

        if i+1 < gState.data.len-fend and
          gState.data[i+1].name in gEnumVals:
          if fname.nBl and gState.addNewIdentifer(fname):
            gState.constStr &= &"{gState.getComments()}\n  {fname}* = ({gState.getNimExpression(gState.data[i+1].val)}).{nname}"
          try:
            count = gState.data[i+1].val.parseInt() + 1
          except:
            count += 1
          i += 2
        else:
          if fname.nBl and gState.addNewIdentifer(fname):
            gState.constStr &= &"{gState.getComments()}\n  {fname}* = {count}.{nname}"
          i += 1
          count += 1

      if node.tsNodeType() == "type_definition" and
        gState.data[^1].name == "type_identifier" and gState.data[^1].val.nBl:
          pDupTypeCommon(nname, fend, gState, true)

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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# enum X {}"

      var
        name = ""
        offset = 0

      if gState.data[0].name == "type_identifier":
        name = gState.data[0].val
        offset = 1

      pEnumCommon(ast, node, name, offset, 0, gState)
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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# typedef enum {}"

      var
        fstart = 0
        fend = 1

      if gState.data[^2].name == "pointer_declarator":
        fend = 2

      if gState.data[0].name == "type_identifier":
        fstart = 1

        pEnumCommon(ast, node, gState.data[0].val, fstart, fend, gState)
      else:
        pEnumCommon(ast, node, gState.data[^1].val, fstart, fend, gState)
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
    proc (ast: ref Ast, node: TSNode, gState: State) =
      if gState.debug:
        gState.debugStr &= "\n# typ function"

      var
        fptr = ""
        i = 1

      while i < gState.data.len:
        if gState.data[i].name == "function_declarator":
          i += 1
          continue

        fptr = ""
        while i < gState.data.len and gState.data[i].name == "pointer_declarator":
          fptr &= "ptr "
          i += 1

        var
          fname = gState.data[i].val
          fnname = gState.getIdentifier(fname, nskProc)
          pout, pname, ptyp, pptr = ""
          count = 1
          flen = ""
          fVar = false

        i += 1
        if i < gState.data.len and gState.data[i].name == "pointer_declarator":
          fVar = true
          i += 1

        while i < gState.data.len:
          if gState.data[i].name == "function_declarator":
            break

          funcParamCommon(fnname, pname, ptyp, pptr, pout, count, i, flen)

        if pout.nBl and pout[^2 .. ^1] == ", ":
          pout = pout[0 .. ^3]

        if not fnname.nBl:
          let
            override = gState.getOverride(fname, nskProc)
          if override.nBl:
            gState.typeStr &= &"{gState.getComments()}\n{override}"
        elif gState.addNewIdentifer(fnname):
          let
            ftyp = gState.getIdentifier(gState.data[0].val, nskType, fnname).getType()
            pragma = gState.getPragma(gState.getImportC(fname, fnname), "cdecl")

          if fptr.nBl or ftyp != "object":
            if fVar:
              gState.procStr &= &"{gState.getComments(true)}\nvar {fnname}*: proc ({pout}): {getPtrType(fptr&ftyp)}{{.cdecl.}}"
            else:
              gState.procStr &= &"{gState.getComments(true)}\nproc {fnname}*({pout}): {getPtrType(fptr&ftyp)}{pragma}"
          else:
            if fVar:
              gState.procStr &= &"{gState.getComments(true)}\nvar {fnname}*: proc ({pout}){{.cdecl.}}"
            else:
              gState.procStr &= &"{gState.getComments(true)}\nproc {fnname}*({pout}){pragma}"
  ))

  # // comment
  result.add((&"""
   (comment
   )
  """,
    proc (ast: ref Ast, node: TSNode, gState: State) =
      let
        cmt = $gState.getNodeVal(node)

      for line in cmt.splitLines():
        let
          line = line.multiReplace([("//", ""), ("/*", ""), ("*/", "")])

        gState.commentStr &= &"\n  # {line.strip(leading=false)}"
  ))

  # // unknown
  result.add((&"""
   (type_definition|struct_specifier|union_specifier|enum_specifier|declaration
    (^.*)
   )
  """,
    proc (ast: ref Ast, node: TSNode, gState: State) =
      var
        done = false
      for i in gState.data:
        case $node.tsNodeType()
        of "declaration":
          if i.name == "identifier":
            let
              override = gState.getOverride(i.val, nskProc)

            if override.nBl:
              gState.procStr &= &"{gState.getComments(true)}\n{override}"
              done = true
              break
            else:
              gState.procStr &= &"{gState.getComments(true)}\n# Declaration '{i.val}' skipped"

        else:
          if i.name == "type_identifier":
            let
              override = gState.getOverride(i.val, nskType)

            if override.nBl:
              gState.typeStr &= &"{gState.getComments()}\n{override}"
              done = true
              break
            else:
              gState.typeStr &= &"{gState.getComments()}\n  # Type '{i.val}' skipped"

      if gState.debug and not done:
        gState.skipStr &= &"\n{gState.getNodeVal(node)}"
  ))

proc initRegex(ast: ref Ast) =
  if ast.children.nBl:
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
  const grammars = initGrammar()

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

proc printGrammar*(gState: State, astTable: AstTable) =
  for name in astTable.keys():
    for ast in astTable[name]:
      gecho ast.printAst()
