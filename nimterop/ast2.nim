import macros, os, sequtils, sets, strformat, strutils, tables, times

import regex

import compiler/[ast, idents, lineinfos, modulegraphs, msgs, options, parser, renderer]

import "."/treesitter/api

import "."/[globals, getters]

proc getPtrType*(str: string): string =
  result = case str:
    of "cchar":
      "cstring"
    of "object":
      "pointer"
    else:
      str

proc handleError*(conf: ConfigRef, info: TLineInfo, msg: TMsgKind, arg: string) =
  # Raise exception in parseString() instead of exiting for errors
  if msg < warnMin:
    raise newException(Exception, msgKindToString(msg))

proc parseString(nimState: NimState, str: string): PNode =
  # Parse a string into Nim AST - use custom error handler that raises
  # an exception rather than exiting on failure
  try:
    result = parseString(
      str, nimState.identCache, nimState.config, errorHandler = handleError
    )
  except:
    decho getCurrentExceptionMsg()

proc getLit*(nimState: NimState, str: string, expression = false): PNode =
  # Used to convert #define literals into const and expressions
  # in array sizes
  #
  # `expression` is true when `str` should be converted into a Nim expression
  let
    str = str.replace(re"/[/*].*?(?:\*/)?$", "").strip()

  if str.contains(re"^[\-]?[\d]+$"):              # decimal
    result = newIntNode(nkIntLit, parseInt(str))

  elif str.contains(re"^[\-]?[\d]*[.]?[\d]+$"):   # float
    result = newFloatNode(nkFloatLit, parseFloat(str))

  elif str.contains(re"^0x[\da-fA-F]+$"):         # hexadecimal
    result = nimState.parseString(str)

  elif str.contains(re"^'[[:ascii:]]'$"):         # char
    result = newNode(nkCharLit)
    result.intVal = str[1].int64

  elif str.contains(re"""^"[[:ascii:]]+"$"""):    # char *
    result = newStrNode(nkStrLit, str[1 .. ^2])

  else:
    let
      str =
        if expression: nimState.getNimExpression(str)
        else: str
    result = nimState.parseString(str)

  if result.isNil:
    result = newNode(nkNilLit)

proc getOverrideOrSkip(nimState: NimState, node: TSNode, origname: string, kind: NimSymKind): PNode =
  # Check if symbol `origname` of `kind` and `origname` has any cOverride defined
  # and use that if present
  #
  # If not, symbol needs to be skipped - only get here if `name` is blank
  let
    # Get cleaned name for symbol, set parent so that cOverride is ignored
    name = nimState.getIdentifier(origname, kind, parent = "override")

    override = nimState.getOverride(origname, kind)

  var
    skind = getKeyword(kind) & " "
  if override.nBl:
    if kind == nskProc:
      skind = ""
    let
      pnode = nimState.parseString(skind & override.replace(origname, name))
    if not pnode.isNil:
      result = pnode[0][0]
  else:
    necho &"\n# $1'{origname}' skipped" % skind
    if nimState.gState.debug:
      nimState.skipStr &= &"\n{nimState.getNodeVal(node)}"

proc addOverrideFinal(nimState: NimState, kind: NimSymKind) =
  # Add all unused cOverride symbols for `kind` to AST
  var
    syms = nimState.getOverrideFinal(kind)
    skind = getKeyword(kind) & "\n"
  if kind == nskProc:
    skind = ""

  if syms.nBl:
    var
      nsyms = nimState.parseString(skind & syms)
    if not nsyms.isNil:
      let
        list =
          if kind == nskProc:
            nsyms.sons
          else:
            nsyms[0].sons
      case kind
      of nskConst:
        nimState.constSection.sons.insert(list, 0)
      of nskType:
        nimState.typeSection.sons.insert(list, 0)
      of nskProc:
        nimState.procSection.sons.insert(list, 0)
      else:
        discard

proc addAllOverrideFinal(nimState: NimState) =
  # Add all unused cOverride symbols to AST
  for kind in [nskConst, nskType, nskProc]:
    nimState.addOverrideFinal(kind)

proc newConstDef(nimState: NimState, node: TSNode, fname = "", fval = ""): PNode =
  # Create an nkConstDef PNode
  #
  # If `fname` or `fval` are set, use them as name and val
  let
    origname =
      if fname.nBl:
        fname
      else:
        # node[0] = identifier = const name
        nimState.getNodeVal(node.getAtom())

    name = nimState.getIdentifier(origname, nskConst)
    info = nimState.getLineInfo(node)
    ident = nimState.getIdent(name, info)

    # node[1] = preproc_arg = value
    val =
      if fval.nBl:
        fval
      else:
        nimState.getNodeVal(node[1])
    valident =
      nimState.getLit(val)

  if name.Bl:
    # Name skipped or overridden since blank
    result = nimState.getOverrideOrSkip(node, origname, nskConst)
  elif valident.kind in {nkCharLit .. nkStrLit} or
    (valident.kind == nkStmtList and valident.len > 0 and
    valident[0].kind in {nkCharLit .. nkStrLit}):
    if nimState.addNewIdentifer(name):
      # const X* = Y
      #
      # nkConstDef(
      #  nkPostfix(
      #   nkIdent("*"),
      #   nkIdent("X")
      #  ),
      #  nkEmpty(),
      #  nkXLit(Y)
      # )
      result = newNode(nkConstDef)
      result.add ident
      result.add newNode(nkEmpty)
      if valident.kind == nkStmtList and valident.len == 1:
        # Collapse single line statement
        result.add valident[0]
      else:
        result.add valident
    else:
      necho &"# const '{origname}' is duplicate, skipped"
  else:
    necho &"# const '{origname}' has invalid value '{val}'"

proc addConst(nimState: NimState, node: TSNode) =
  # Add a const to the AST
  #
  # #define X Y
  #
  # (preproc_def
  #  (identifier)
  #  (preproc_arg)
  # )
  decho("addConst()")
  nimState.printDebug(node)

  if node[0].getName() == "identifier" and
    node[1].getName() == "preproc_arg":
    let
      constDef = nimState.newConstDef(node)

    if not constDef.isNil:
      # nkConstSection.add
      nimState.constSection.add constDef
      nimState.constIdentifiers.incl constDef.getIdentName()

      nimState.printDebug(constDef)

proc addPragma(nimState: NimState, node: TSNode, pragma: PNode, name: string, value: PNode = nil) =
  # Add pragma to an existing nkPragma tree
  let
    pinfo = nimState.getLineInfo(node.getAtom())
    pident = nimState.getIdent(name, pinfo, exported = false)

  if value.isNil:
    pragma.add pident
  else:
    let
      colExpr = newNode(nkExprColonExpr)
    colExpr.add pident
    colExpr.add value
    pragma.add colExpr

proc addPragma(nimState: NimState, node: TSNode, pragma: PNode, pragmas: seq[string]) =
  # Add sequence of pragmas to an existing nkPragma tree
  for name in pragmas:
    nimState.addPragma(node, pragma, name)

proc addPragma(nimState: NimState, node: TSNode, pragma: PNode, pragmas: OrderedTable[string, PNode]) =
  # Add a table of name:value pragmas to an existing nkPragma tree
  for name, value in pragmas.pairs:
    nimState.addPragma(node, pragma, name, value)

proc newPragma(nimState: NimState, node: TSNode, name: string, value: PNode = nil): PNode =
  # Create nkPragma tree for name:value
  #
  # {.name1, name2: value2.}
  #
  # nkPragma(
  #  nkIdent(name1),
  #  nkExprColonExpr(
  #   nkIdent(name2),
  #   nkStrLit(value2)
  #  )
  # )
  result = newNode(nkPragma)
  nimState.addPragma(node, result, name, value)

proc newPragma(nimState: NimState, node: TSNode, pragmas: seq[string] | OrderedTable[string, PNode]): PNode =
  # Create nkPragma tree for multiple name:value
  result = newNode(nkPragma)
  nimState.addPragma(node, result, pragmas)

proc newPragmaExpr(nimState: NimState, node: TSNode, ident: PNode, name: string, value: PNode = nil): PNode =
  # Create nkPragmaExpr tree for name:value
  #
  # nkPragmaExpr(
  #  nkPostfix(
  #   nkIdent("*"),
  #   nkIdent("X")
  #  ),
  #  nkPragma(
  #   nkIdent(name1),
  #   nkExprColonExpr(
  #    nkIdent(name2),
  #    nkStrLit(value2)
  #   )
  #  )
  # )
  result = newNode(nkPragmaExpr)
  result.add ident
  result.add nimState.newPragma(node, name, value)

proc newPragmaExpr(nimState: NimState, node: TSNode, ident: PNode, pragmas: seq[string] | OrderedTable[string, PNode]): PNode =
  # Create nkPragmaExpr tree for multiple name:value
  result = newNode(nkPragmaExpr)
  result.add ident
  result.add nimState.newPragma(node, pragmas)

proc newXIdent(nimState: NimState, node: TSNode, kind = nskType, fname = "", pragmas: seq[string] = @[], istype = false): PNode =
  # Create nkTypeDef PNode with first ident if `nskType`
  # Create nkIdentDefs PNode with first ident if `nskVar`
  # Create an nkPostfix node for `nskProc`
  #
  # If `fname`, use it instead of node.getAtom() for name
  # If `pragmas`, add as nkPragmaExpr but not for `nskProc` since procs add pragmas elsewhere
  # If `istype` is set, this is a typedef, else struct/union so add {.importc: "struct/union X".} when includeHeader
  let
    atom = node.getAtom()

    (tname, torigname, info) =
      if not atom.isNil:
        nimState.getNameInfo(node.getAtom(), kind)
      else:
        ("", "", nimState.getLineInfo(node))

    origname =
      if fname.nBl:
        fname
      else:
        torigname

    # Process name if forced, getNameInfo() already runs getIdentifier()
    name =
      if fname.nBl:
        nimState.getIdentifier(fname, kind)
      else:
        tname

    ident = nimState.getIdent(name, info)

  if name.Bl:
    # Name skipped or overridden since blank
    result = nimState.getOverrideOrSkip(node, origname, kind)
  elif nimState.addNewIdentifer(name):
    if kind == nskType:
      # type name* =
      #
      # nkTypeDef(
      #  nkPostfix(
      #   nkIdent("*"),
      #   nkIdent(name)
      #  ),
      #  nkEmpty()
      # )
      #
      # type name* {.bycopy, importc: "abc".} =
      #
      # nkTypeDef(
      #  nkPragmaExpr(
      #   nkPostfix(
      #    nkIdent("*"),
      #    nkIdent(name)
      #   ),
      #   nkPragma(
      #    nkIdent("bycopy"),
      #    nkExprColonExpr(
      #     nkIdent("importc"),
      #     nkStrLit("abc")
      #    )
      #   )
      #  ),
      #  nkEmpty()
      # )
      var
        pragmas =
          if nimState.includeHeader:
            # Need to add header and importc
            if istype and name == origname:
              # Need to add impShort since neither struct/union nor name change
              pragmas & nimState.impShort
            else:
              # Add header shortcut, additional pragmas added later
              pragmas & (nimState.impShort & "H")
          else:
            pragmas

        prident =
          if pragmas.nBl:
            nimState.newPragmaExpr(node, ident, pragmas)
          else:
            ident

      if nimState.includeHeader:
        if not istype or name != origname:
          # Add importc pragma since either struct/union or name changed
          let
            uors =
              if not istype:
                if "union" in pragmas:
                  "union "
                else:
                  "struct "
              else:
                ""
          nimState.addPragma(node, prident[1], "importc", newStrNode(nkStrLit, &"{uors}{origname}"))

      result = newNode(nkTypeDef)
      result.add prident
      result.add newNode(nkEmpty)
    elif kind == nskVar:
      # var name* {.importc: "abc".}
      #
      # nkIdentDefs(
      #  nkPragmaExpr(
      #   nkPostfix(
      #    nkIdent("*"),
      #    nkIdent(name)
      #   ),
      #   nkPragma(
      #    nkExprColonExpr(
      #     nkIdent("importc"),
      #     nkStrLit("abc")
      #    )
      #   )
      #  )
      # )
      let
        prident = block:
          var
            prident: PNode
          if name != origname:
            # Add importc pragma since name changed
            prident = nimState.newPragmaExpr(node, ident, "importc", newStrNode(nkStrLit, &"{origname}"))
            if nimState.includeHeader():
              # Add header
              nimState.addPragma(node, prident[1], nimState.impShort & "H")
            elif nimState.gState.dynlib.nBl:
              # Add dynlib
              nimState.addPragma(node, prident[1], "dynlib", nimState.getIdent(nimState.gState.dynlib))
          else:
            # Only need impShort since no name change
            prident = nimState.newPragmaExpr(node, ident, nimState.impShort)
          if pragmas.nBl:
            nimState.addPragma(node, prident[1], pragmas)
          prident

      result = newNode(nkIdentDefs)
      result.add prident
    elif kind == nskProc:
      # name*
      #
      # nkPostfix(
      #  nkIdent("*"),
      #  nkIdent(name)
      # )
      #
      # No pragmas here since proc pragmas are elsewhere in the AST
      result = ident

    nimState.identifierNodes[name] = result
  else:
    necho &"# $1 '{origname}' is duplicate, skipped" % getKeyword(kind)

proc newPtrTree(nimState: NimState, count: int, typ: PNode): PNode =
  # Create nkPtrTy tree depending on count
  #
  # Reduce by 1 if Nim type available for ptr X - e.g. ptr cchar = cstring
  result = typ
  var
    count = count
  if typ.kind == nkIdent:
    let
      tname = typ.ident.s
      ptname = getPtrType(tname)
    if tname != ptname:
      # If Nim type available, use that ident
      result = nimState.getIdent(ptname, typ.info, exported = false)
      # One ptr reduced
      count -= 1
  if count > 0:
    # Nested nkPtrTy(typ) depending on count
    #
    # [ptr ...] typ
    #
    # nkPtrTy(
    #  nkPtrTy(
    #    typ
    #  )
    # )
    var
      nresult = newNode(nkPtrTy)
      parent = nresult
      child: PNode
    for i in 1 ..< count:
      child = newNode(nkPtrTy)
      parent.add child
      parent = child
    parent.add result
    result = nresult

proc newArrayTree(nimState: NimState, node: TSNode, typ, size: PNode = nil): PNode =
  # Create nkBracketExpr tree depending on input
  #
  # If `size` is nil, create UncheckedArray[typ]
  let
    info = nimState.getLineInfo(node.getAtom())
    tname =
      if size.isNil:
        "UncheckedArray"
      else:
        "array"
    ident = nimState.getIdent(tname, info, exported = false)

  # array[size, typ]
  #
  # nkBracketExpr(
  #  nkIdent("array"),
  #  size,
  #  typ
  # )
  result = newNode(nkBracketExpr)
  result.add ident
  if not size.isNil:
    result.add size
  result.add typ

proc getTypeArray(nimState: NimState, node, tnode: TSNode, name: string): PNode
proc getTypeProc(nimState: NimState, name: string, node, rnode: TSNode): PNode

iterator newIdentDefs(nimState: NimState, name: string, node: TSNode, offset: SomeInteger, exported = false): PNode =
  # Create nkIdentDefs tree for specified proc parameter or object field
  #
  # For proc, param should not be exported
  #
  # pname: [ptr ..] typ
  #
  # nkIdentDefs(
  #  nkIdent(pname),
  #  typ,
  #  nkEmpty()
  # )
  #
  # For object, field should be exported
  #
  # pname*: [ptr ..] typ
  #
  # nkIdentDefs(
  #  nkPostfix(
  #   nkIdent("*"),
  #   nkIdent(pname)
  #  ),
  #  typ,
  #  nkEmpty()
  # )
  #
  # Iterator since structs can have multiple comma separated fields for the
  # same type so can yield multiple results.
  #
  # struct ABC { int w, h; };
  #
  # This is not applicable for procs.
  let
    start = getStartAtom(node)

    # node[start] - param type
    (tname, _, tinfo) = nimState.getNameInfo(node[start].getAtom(), nskType, parent = name)
    tident = nimState.getIdent(tname, tinfo, exported = false)

  if start == node.len - 1:
    # Only for proc with no named param - create a param name based on offset
    #
    # int func(char, int);
    var
      result = newNode(nkIdentDefs)

    if tname != "object":
      let
        pname = "a" & $(offset+1)
        pident = nimState.getIdent(pname, tinfo, exported)
      result.add pident
      result.add tident
      result.add newNode(nkEmpty)
    else:
      # int func(void)
      result = nil

    yield result
  else:
    for i in start+1 ..< node.len:
      if node[i].getName() == "bitfield_clause":
        continue

      var
        result = newNode(nkIdentDefs)

      let
        fdecl = node[i].firstChildInTree("function_declarator")
        afdecl = node[i].firstChildInTree("abstract_function_declarator")
        adecl = node[i].firstChildInTree("array_declarator")
        abst = node[i].getName() == "abstract_pointer_declarator"
      if fdecl.isNil and afdecl.isNil and adecl.isNil:
        if abst:
          # Only for proc with no named param with pointer type
          # Create a param name based on offset
          #
          # int func(char *, int **);
          let
            pname = "a" & $(offset+1)
            pident = nimState.getIdent(pname, tinfo, exported)
            acount = node[i].getXCount("abstract_pointer_declarator")
          result.add pident
          result.add nimState.newPtrTree(acount, tident)
          result.add newNode(nkEmpty)
        else:
          # Named param, simple type
          let
            (pname, _, pinfo) = nimState.getNameInfo(node[i].getAtom(), nskField, parent = name)
            pident = nimState.getIdent(pname, pinfo, exported)

            # Bitfield support - typedef struct { int field: 1; };
            prident =
              if node.len > i and node[i + 1].getName() == "bitfield_clause":
                nimState.newPragmaExpr(node, pident, "bitsize",
                  newIntNode(nkIntLit, parseInt(nimState.getNodeVal(node[i + 1].getAtom()))))
              else:
                pident

            count = node[i].getPtrCount()

          result.add prident
          if count > 0:
            result.add nimState.newPtrTree(count, tident)
          else:
            result.add tident
          result.add newNode(nkEmpty)
      elif not fdecl.isNil:
        # Named param, function pointer
        let
          (pname, _, pinfo) = nimState.getNameInfo(node[i].getAtom(), nskField, parent = name)
          pident = nimState.getIdent(pname, pinfo, exported)
        result.add pident
        result.add nimState.getTypeProc(name, node[i], node[start])
        result.add newNode(nkEmpty)
      elif not afdecl.isNil:
        # Only for proc with no named param with function pointer type
        # Create a param name based on offset
        #
        # int func(int (*)(int *));
        let
          pname = "a" & $(offset+1)
          pident = nimState.getIdent(pname, tinfo, exported)
          procTy = nimState.getTypeProc(name, node[i], node[start])
        result.add pident
        result.add procTy
        result.add newNode(nkEmpty)
      elif not adecl.isNil:
        # Named param, array type
        let
          (pname, _, pinfo) = nimState.getNameInfo(node[i].getAtom(), nskField, parent = name)
          pident = nimState.getIdent(pname, pinfo, exported)
        result.add pident
        result.add nimState.getTypeArray(node[i], node[start], name)
        result.add newNode(nkEmpty)
      else:
        result = nil

      yield result

proc newFormalParams(nimState: NimState, name: string, node: TSNode, rtyp: PNode): PNode =
  # Create nkFormalParams tree for specified params and return type
  #
  # proc(pname: ptyp ..): rtyp
  #
  #  nkFormalParams(
  #   rtyp,
  #   nkIdentDefs(     # multiple depending on params
  #    ..
  #   )
  #  )
  result = newNode(nkFormalParams)

  # Add return type
  result.add rtyp

  if not node.isNil:
    for i in 0 ..< node.len:
      if node[i].getName() == "parameter_declaration":
        # Add nkIdentDefs for each param
        for param in nimState.newIdentDefs(name, node[i], i, exported = false):
          if not param.isNil:
            result.add param

proc newProcTy(nimState: NimState, name: string, node: TSNode, rtyp: PNode): PNode =
  # Create nkProcTy tree for specified proc type

  # proc(pname: ptyp ..): rtyp
  #
  # nkProcTy(
  #  nkFormalParams(
  #   rtyp,
  #   nkIdentDefs(     # multiple depending on params
  #    ..
  #   )
  #  ),
  #  nkPragma(...)
  # )
  result = newNode(nkProcTy)
  result.add nimState.newFormalParams(name, node, rtyp)
  result.add nimState.newPragma(node, nimState.gState.convention)

proc newRecListTree(nimState: NimState, name: string, node: TSNode): PNode =
  # Create nkRecList tree for specified object
  if not node.isNil:
    # fname*: ftyp
    # ..
    #
    # nkRecList(
    #  nkIdentDefs(      # multiple depending on fields
    #   ..
    #  )
    # )
    result = newNode(nkRecList)

    for i in 0 ..< node.len:
      if node[i].getName() == "field_declaration":
        # Add nkIdentDefs for each field
        for field in nimState.newIdentDefs(name, node[i], i, exported = true):
          if not field.isNil:
            result.add field

proc addTypeObject(nimState: NimState, node: TSNode, typeDef: PNode = nil, fname = "", istype = false, union = false) =
  # Add a type of object
  #
  # If `typeDef` is set, use it instead of creating new PNode
  # If `fname` is set, use it as the name when creating new PNode
  # If `istype` is set, this is a typedef, else struct/union
  decho("addTypeObject()")
  let
    # Object has fields or not
    fdlist = node.anyChildInTree("field_declaration_list")

    pragmas = block:
      var pragmas =
        if union:
          @["union"]
        else:
          @[]
      if not fdlist.isNil and fdlist.len > 0:
        # Object with fields should be bycopy
        pragmas.add "bycopy"
      else:
        # Incomplete, might get forward declared
        pragmas.add "incompleteStruct"

      pragmas

    typeDefExisting = not typeDef.isNil

    typeDef =
      if typeDef.isNil:
        nimState.newXIdent(node, fname = fname, pragmas = pragmas, istype = istype)
      else:
        typeDef

  if not typeDef.isNil:
    # type X* = object
    #
    # nkTypeDef(
    #  nkPostfix(
    #   nkIdent("*"),
    #   nkIdent("X")
    #  ),
    #  nkEmpty(),
    #  nkObjectTy(
    #   nkEmpty(),
    #   nkEmpty(),
    #   nkEmpty()
    #  )
    # )
    #
    # type
    #   X* {.bycopy.} = object
    #     field1*: cint
    #
    # nkTypeDef(
    #  nkPragmaExpr(
    #   nkPostfix(
    #    nkIdent("*"),
    #    nkIdent("X")
    #   ),
    #   nkPragma(
    #    nkIdent("bycopy")
    #   )
    #  ),
    #  nkEmpty(),
    #  nkObjectTy(
    #   nkEmpty(),
    #   nkEmpty(),
    #   nkRecList(
    #    nkIdentDefs(
    #     nkPostfix(
    #      nkIdent("*"),
    #      nkIdent("field1")
    #     ),
    #     nkIdent("cint"),
    #     nkEmpty()
    #    )
    #   )
    #  )
    # )
    let
      name = typeDef.getIdentName()
      obj = newNode(nkObjectTy)
    obj.add newNode(nkEmpty)
    obj.add newNode(nkEmpty)

    if not fdlist.isNil and fdlist.len > 0:
      # Add fields to object if present
      obj.add nimState.newRecListTree(name, fdlist)
    else:
      obj.add newNode(nkEmpty)

    typeDef.add obj

    # If typeDef was passed in, need to add pragmas if any
    if pragmas.nBl and typeDefExisting:
      if typeDef[0].kind != nkPragmaExpr:
        let
          npexpr = nimState.newPragmaExpr(node, typedef[0], pragmas)
        typedef[0] = npexpr
      else:
        # includeHeader already added impShort in newXIdent()
        nimState.addPragma(node, typeDef[0][1], pragmas)

    # nkTypeSection.add
    nimState.typeSection.add typeDef

    nimState.printDebug(typeDef)
  else:
    # Forward declaration case
    let
      fdlist = node.anyChildInTree("field_declaration_list")
    if not fdlist.isNil and fdlist.len > 0:
      # Current node has fields
      let
        origname = nimState.getNodeVal(node.getAtom())

        # Fix issue #185
        name =
          if origname.nBl:
            nimState.getIdentifier(origname, nskType)
          else:
            ""

      if name.nBl and nimState.identifierNodes.hasKey(name):
        let
          def = nimState.identifierNodes[name]
        # Duplicate nkTypeDef for `name` with empty fields
        if def.kind == nkTypeDef and def.len == 3 and
          def[2].kind == nkObjectTy and def[2].len == 3 and
          def[2][2].kind == nkEmpty:
            # Add fields to existing object
            def[2][2] = nimState.newRecListTree(name, fdlist)

            # Change incompleteStruct to bycopy pragma
            if def[0].kind == nkPragmaExpr and def[0].len == 2 and
              def[0][1].kind == nkPragma and def[0][1].len > 0:
                for i in 0 ..< def[0][1].len:
                  if $def[0][1][i] == "incompleteStruct":
                    def[0][1][i] = nimState.getIdent(
                      "bycopy", nimState.getLineInfo(node.getAtom()),
                      exported = false
                    )

            nimState.printDebug(def)

proc addTypeTyped(nimState: NimState, node: TSNode, ftname = "", offset = 0) =
  # Add a type of a specified type
  #
  # If `ftname` is set, use it as the type name
  # If `offset` is set, skip `offset` names, since created already
  decho("addTypeTyped()")
  let
    start = getStartAtom(node)
  for i in start+1+offset ..< node.len:
    # Add a type of a specific type
    let
      # node[i] = identifer = name
      typeDef = nimState.newXIdent(node[i], istype = true)

    if not typeDef.isNil:
      let
        name = typeDef.getIdentName()

        # node[start] = identifier = type name
        (tname0, _, tinfo) = nimState.getNameInfo(node[start].getAtom(), nskType, parent = name)

        # Override type name
        tname =
          if ftname.nBl:
            ftname
          else:
            tname0

        ident = nimState.getIdent(tname, tinfo, exported = false)

        # node[i] could have nested pointers
        count = node[i].getPtrCount()

      # Skip typedef X X;
      if name != tname:
        if count > 0:
          # If pointers
          typeDef.add nimState.newPtrTree(count, ident)
        else:
          typeDef.add ident

        # type X* = [ptr ..] Y
        #
        # nkTypeDef(
        #  nkPostfix(
        #   nkIdent("*"),
        #   nkIdent("X")
        #  ),
        #  nkEmpty(),
        #  nkPtrTy(            # optional, nested
        #   nkIdent("Y")
        #  )
        # )

        # nkTypeSection.add
        nimState.typeSection.add typeDef

        nimState.printDebug(typeDef)
      else:
        nimState.addTypeObject(node, typeDef = typeDef, istype = true)

proc getTypeArray(nimState: NimState, node, tnode: TSNode, name: string): PNode =
  # Create array type tree
  let
    # tnode = identifier = type name
    (tname, _, info) = nimState.getNameInfo(tnode.getAtom(), nskType, parent = name)
    ident = nimState.getIdent(tname, info, exported = false)

    # Top-most array declarator
    adecl = node.firstChildInTree("array_declarator")

    # node could have nested arrays
    acount = adecl.getArrayCount()
    innermost = adecl.mostNestedChildInTree()

    # node could have nested pointers - type
    tcount = node.getPtrCount()

    # Name could be nested pointer to array
    #
    # (..
    #  (array_declarator
    #   (parenthesized_declarator
    #    (pointer_declarator ..
    #     (pointer_declarator          <- search upwards from atom
    #      (type_identifier)           <- atom
    #     )
    #    )
    #   )
    #  )
    # )
    ncount = innermost[0].getAtom().tsNodeParent().getPtrCount(reverse = true)

  result = ident
  var
    cnode = adecl

  if tcount > 0:
    # If pointers
    result = nimState.newPtrTree(tcount, result)

  for i in 0 ..< acount:
    if cnode.len == 2:
      # type name[X] => array[X, type]
      let
        # Size of array could be a Nim expression
        size = nimState.getLit(nimState.getNodeVal(cnode[1]), expression = true)
      if size.kind != nkNilLit:
        result = nimState.newArrayTree(cnode, result, size)
        cnode = cnode[0]
    elif cnode.len == 1:
      # type name[] = UncheckedArray[type]
      result = nimState.newArrayTree(cnode, result)
      cnode = cnode[0]

  if ncount > 0:
    result = nimState.newPtrTree(ncount, result)

proc addTypeArray(nimState: NimState, node: TSNode) =
  # Add a type of array type
  decho("addTypeArray()")
  let
    start = getStartAtom(node)

    # node[start] = type name
    tnode = node[start]

  # Could have multiple types, comma separated
  for i in start+1 ..< node.len:
    let
      # node[i] = identifer = name
      typeDef = nimState.newXIdent(node[i], istype = true)

    if not typeDef.isNil:
      let
        name = typeDef.getIdentName()
        typ = nimState.getTypeArray(node[i], tnode, name)

      typeDef.add typ

      # type X* = [ptr] array[x, [ptr] Y]
      #
      # nkTypeDef(
      #  nkPostfix(
      #   nkIdent("*"),
      #   nkIdent("X")
      #  ),
      #  nkEmpty(),
      #  nkPtrTy(              # optional, nested
      #   nkBracketExpr(
      #    nkIdent("array")
      #    nkXLit(x),
      #    nkPtrTy(            # optional, nested
      #     nkIdent("Y")
      #    )
      #   )
      #  )
      # )

      # nkTypeSection.add
      nimState.typeSection.add typeDef

      nimState.printDebug(typeDef)

proc getTypeProc(nimState: NimState, name: string, node, rnode: TSNode): PNode =
  # Create proc type tree
  #
  # `rnode` is the return type
  let
    # rnode = identifier = return type name
    (rname, _, rinfo) = nimState.getNameInfo(rnode.getAtom(), nskType, parent = name)

    # Parameter list
    plist = node.anyChildInTree("parameter_list")

    # node could have nested pointers
    tcount = node.getPtrCount()

    # Nameless function pointer
    afdecl = node.firstChildInTree("abstract_function_declarator")

    # Name could be nested pointer to function
    #
    # (..
    #  (function_declarator
    #   (parenthesized_declarator
    #    (pointer_declarator ..
    #     (pointer_declarator          <- search upwards from atom
    #      (type_identifier)           <- atom
    #     )
    #    )
    #   )
    #  )
    # )
    ncount =
      if not afdecl.isNil:
        # Pointer to function pointer
        afdecl[0].getXCount("abstract_pointer_declarator")
      else:
        node.getAtom().tsNodeParent().getPtrCount(reverse = true)

  # Return type
  var
    retType =
      if rname == "object" and tcount == 0:
        # void (*func)(..)
        newNode(nkEmpty)
      else:
        nimState.getIdent(rname, rinfo, exported = false)
  if tcount > 0:
    retType = nimState.newPtrTree(tcount, retType)

  # Proc with return type and params
  result = nimState.newProcTy(name, plist, retType)
  if ncount > 1:
    result = nimState.newPtrTree(ncount-1, result)

proc addTypeProc(nimState: NimState, node: TSNode) =
  # Add a type of proc type
  decho("addTypeProc()")
  let
    start = getStartAtom(node)

    # node[start] = return type
    rnode = node[start]

  # Could have multiple types, comma separated
  for i in start+1 ..< node.len:
    let
      # node[i] = identifier = name
      typeDef = nimState.newXIdent(node[i], istype = true)

    if not typeDef.isNil:
      let
        name = typeDef.getIdentName()

        procTy = nimState.getTypeProc(name, node[i], rnode)

      typeDef.add procTy

      # type X* = proc(a1: Y, a2: Z): P
      #
      # nkTypeDef(
      #  nkPostfix(
      #   nkIdent("*"),
      #   nkIdent("X")
      #  ),
      #  nkEmpty(),
      #  nkPtrTy(              # optional, nested
      #   nkProcTy(
      #    nkFormalParams(
      #     nkPtrTy(           # optional, nested
      #      nkIdent(retType)
      #     ),
      #     nkIdentDefs(
      #      nkIdent(param),
      #      nkPtrTy(
      #       nkIdent(ptype)
      #      ),
      #      nkEmpty()
      #     ),
      #     ...
      #    ),
      #    nkPragma(...)
      #   )
      #  )
      # )

      # nkTypeSection.add
      nimState.typeSection.add typeDef

      nimState.printDebug(typeDef)

proc addType(nimState: NimState, node: TSNode, union = false) =
  decho("addType()")
  nimState.printDebug(node)

  if node.getName() in ["struct_specifier", "union_specifier"]:
    # struct X;
    #
    # (struct_specifier
    #  (type_identifier)
    # )
    #
    # struct X {};
    #
    # (struct_specifier
    #  (type_identifier)
    #  (field_declaration_list = "{}")
    # )
    #
    # struct X { char *a1; };
    #
    # (struct_specifier
    #  (type_identifier)
    #  (field_declaration_list
    #   (field_declaration
    #    (type_identifier|primitive_type|)
    #    (struct_specifier
    #     (type_identifier)
    #    )
    #
    #    (field_identifier)
    #   )
    #   (field_declaration ...)
    #  )
    decho("addType(): case 1")
    nimState.addTypeObject(node, union = union)
  elif node.getName() == "type_definition":
    if node.len >= 2:
      let
        fdlist = node[0].anyChildInTree("field_declaration_list")
      if (fdlist.isNil or (not fdlist.isNil and fdlist.Bl)) and
          nimState.getNodeVal(node[1]) == "":
        # typedef struct X;
        #
        # (type_definition
        #  (struct_specifier
        #   (type_identifier)
        #  )
        #  (type_definition = "")
        # )
        #
        # typedef struct X {};
        #
        # (type_definition
        #  (struct_specifier
        #   (type_identifier)
        #   (field_declaration_list = "{}")
        #  )
        #  (type_definition = "")
        # )
        decho("addType(): case 2")
        nimState.addTypeObject(node[0], union = union)
      else:
        let
          fdecl = node[1].anyChildInTree("function_declarator")
          adecl = node[1].anyChildInTree("array_declarator")
        if fdlist.isNil():
          if adecl.isNil and fdecl.isNil:
            # typedef X Y;
            # typedef X *Y;
            # typedef struct X Y;
            # typedef struct X *Y;
            #
            # (type_definition
            #  (type_qualifier?)
            #  (type_identifier|primitive_type|)
            #  (struct_specifier
            #   (type_identifier)
            #  )
            #
            #  (pointer_declarator - optional, nested
            #   (type_identifier)
            #  )
            # )
            decho("addType(): case 3")
            nimState.addTypeTyped(node)
          elif not fdecl.isNil:
            # typedef X (*Y)(a1, a2, a3);
            # typedef X *(*Y)(a1, a2, a3);
            # typedef struct X (*Y)(a1, a2, a3);
            # typedef struct X *(*Y)(a1, a2, a3);
            #
            # (type_definition
            #  (type_qualifier?)
            #  (type_identifier|primitive_type|)
            #  (struct_specifier
            #   (type_identifier)
            #  )
            #
            #  (pointer_declarator - optional, nested
            #   (function_declarator
            #    (parenthesized_declarator
            #     (pointer_declarator
            #      (type_identifer)
            #     )
            #    )
            #    (parameter_list
            #     (parameter_declaration
            #      (struct_specifier|type_identifier|primitive_type|array_declarator|function_declarator)
            #      (identifier - optional)
            #     )
            #    )
            #   )
            #  )
            # )
            decho("addType(): case 4")
            nimState.addTypeProc(node)
          elif not adecl.isNil:
            # typedef struct X Y[a][..];
            # typedef struct X *Y[a][..];
            # typedef struct X *(*Y)[a][..];
            #
            # (type_definition
            #  (type_qualifier?)
            #  (type_identifier|primitive_type|)
            #  (struct_specifier
            #   (type_identifier)
            #  )
            #
            #  (pointer_declarator - optional, nested
            #   (array_declarator - nested
            #    (pointer_declarator - optional, nested
            #     (type_identifier)
            #    )
            #    (number_literal)
            #   )
            #  )
            # )
            decho("addType(): case 5")
            nimState.addTypeArray(node)
        else:
          if node.firstChildInTree("field_declaration_list").isNil:
            # typedef struct X { .. } Y, *Z;
            #
            # (type_definition
            #  (struct_specifier
            #   (type_identifier) - named struct          <====
            #   (field_declaration_list
            #    (field_declaration - optional, multiple
            #     (type_identifier|primitive_type|)
            #     (function_declarator|array_declarator
            #      ..
            #     )
            #
            #     (field_identifier)
            #    )
            #   )
            #  )
            #
            #  (type_identifier)
            #  (pointer_declarator - optional, nested
            #   (type_identifier)
            #  )
            # )

            # First add struct as object
            decho("addType(): case 6")
            nimState.addTypeObject(node[0], union = union)

            if node.len > 1 and nimState.getNodeVal(node[1]) != "":
              # Add any additional names
              nimState.addTypeTyped(node)
          else:
            # Same as above except unnamed struct
            #
            # typedef struct { .. } Y, *Z;

            # Get any name that isn't a pointer
            decho("addType(): case 7")
            let
              name = block:
                var
                  name = ""
                for i in 1 ..< node.len:
                  if node[i].getName() == "type_identifier":
                    name = nimState.getNodeVal(node[i].getAtom())

                name

            # Now add struct as object with specified name
            nimState.addTypeObject(node[0], fname = name, istype = true, union = union)

            if name.nBl:
              # Add any additional names
              nimState.addTypeTyped(node, ftname = name, offset = 1)

proc addEnum(nimState: NimState, node: TSNode) =
  decho("addEnum()")
  nimState.printDebug(node)

  let
    enumlist = node.anyChildInTree("enumerator_list")
  if not enumlist.isNil:
    var
      name, origname = ""
      offset = 0
      prev = ""

    if node.getAtom().getName() == "type_identifier":
      # [typedef] enum X {} Y;
      # Use X as name
      origname = nimState.getNodeVal(node.getAtom())
    elif node.getName() == "type_definition" and node.len > 1:
      # typedef enum {} Y;
      # Use Y as name
      origname = nimState.getNodeVal(node[1].getAtom())
      offset = 1

    if origname.nBl:
      name = nimState.getIdentifier(origname, nskType)
    else:
      # enum {};
      # Nameless so create a name
      name = nimState.getUniqueIdentifier("Enum")

    if name.Bl:
      # Name skipped or overridden since blank
      let
        eoverride = nimState.getOverrideOrSkip(node, origname, nskType)
      if not eoverride.isNil:
        nimState.typeSection.add eoverride
    elif nimState.addNewIdentifer(name):
      # Add enum definition and helpers
      nimState.enumSection.add nimState.parseString(&"defineEnum({name})")

      # Create const for fields
      var
        fnames: HashSet[string]
      for i in 0 .. enumlist.len - 1:
        let
          en = enumlist[i]
        if en.getName() == "comment":
          continue
        let
          fname = nimState.getIdentifier(nimState.getNodeVal(en.getAtom()), nskEnumField)
        if fname.nBl:
          var
            fval = ""
          if prev.Bl:
            # Starting default value
            fval = &"(0).{name}"
          else:
            # One greater than previous
            fval = &"({prev} + 1).{name}"

          if en.len > 1 and en[1].getName() in gEnumVals:
            # Explicit value
            fval = "(" & nimState.getNimExpression(nimState.getNodeVal(en[1]), name) & ")." & name

          # Cannot use newConstDef() since parseString(fval) adds backticks to and/or
          nimState.constSection.add nimState.parseString(&"const {fname}* = {fval}")[0][0]

          fnames.incl fname

          prev = fname

      # Add fields to list of consts after processing enum so that we don't cast
      # enum field to itself
      nimState.constIdentifiers.incl fnames

      # Add other names
      if node.getName() == "type_definition" and node.len > 1:
        nimState.addTypeTyped(node, ftname = name, offset = offset)

proc addProcVar(nimState: NimState, node, rnode: TSNode) =
  # Add a proc variable
  decho("addProcVar()")
  let
    # node = identifier = name
    identDefs = nimState.newXIdent(node, kind = nskVar, istype = true)

  if not identDefs.isNil:
    let
      name = identDefs.getIdentName()
      # origname = nimState.getNodeVal(node.getAtom())

      procTy = nimState.getTypeProc(name, node, rnode)

    identDefs.add procTy
    identDefs.add newNode(nkEmpty)

    # var X* {.importc: "_X": proc(a1: Y, a2: Z): P {.cdecl.}
    #
    # nkIdentDefs(
    #  nkPragmaExpr(
    #   nkPostfix(
    #    nkIdent("*"),
    #    nkIdent("X")
    #   ),
    #   nkPragma(
    #    nkExprColonExpr(
    #     nkIdent("importc"),
    #     nkStrLit("_X")
    #    )
    #   )
    #  ),
    #  nkProcTy(
    #   nkFormalParams(
    #    nkIdent("P"),
    #    nkIdentDefs(
    #     nkIdent("a1"),
    #     nkIdent("Y"),
    #     nkEmpty()
    #    ),
    #    nkIdentDefs(
    #     nkIdent("a2"),
    #     nkIdent("Z"),
    #     nkEmpty()
    #    )
    #   ),
    #   nkPragma(
    #    nkIdent("cdecl")
    #   )
    #  ),
    #  nkEmpty()
    # )

    # nkVarSection.add
    nimState.varSection.add identDefs

    nimState.printDebug(identDefs)

proc addProc(nimState: NimState, node, rnode: TSNode) =
  # Add a proc
  #
  # `node` is the `nth` child of (declaration)
  # `rnode` is the return value node, the first child of (declaration)
  decho("addProc()")
  let
    # node = identifier = name
    ident = nimState.newXIdent(node, kind = nskProc)

  if not ident.isNil:
    let
      # Only need the ident tree, not nkTypeDef parent
      name = ident.getIdentName()
      origname = nimState.getNodeVal(node.getAtom())

      # node could have nested pointers
      tcount = node.getPtrCount()

      # rnode = identifier = return type name
      (rname, _, rinfo) = nimState.getNameInfo(rnode.getAtom(), nskType, parent = name)

      # Parameter list
      plist = node.anyChildInTree("parameter_list")

      procDef = newNode(nkProcDef)

    # proc X(a1: Y, a2: Z): P {.pragma.}
    #
    # nkProcDef(
    #  nkPostfix(
    #   nkIdent("*"),
    #   nkIdent("X")
    #  ),
    #  nkEmpty(),
    #  nkEmpty(),
    #  nkFormalParams(
    #   nkPtrTy(           # optional, nested
    #    nkIdent(retType)
    #   ),
    #   nkIdentDefs(
    #    nkIdent(param),
    #    nkPtrTy(
    #     nkIdent(ptype)
    #    ),
    #    nkEmpty()
    #   ),
    #   ...
    #  ),
    #  nkPragma(...),
    #  nkEmpty(),
    #  nkEmpty()
    # )

    procDef.add ident
    procDef.add newNode(nkEmpty)
    procDef.add newNode(nkEmpty)

    # Return type
    var
      retType =
        if rname == "object" and tcount == 0:
          # void func(..)
          newNode(nkEmpty)
        else:
          nimState.getIdent(rname, rinfo, exported = false)
    if tcount > 0:
      retType = nimState.newPtrTree(tcount, retType)

    # Proc with return type and params
    procDef.add nimState.newFormalParams(name, plist, retType)

    # Pragmas
    let
      prident =
        if name != origname:
          # Explicit {.importc: "origname".}
          nimState.newPragma(node, "importc", newStrNode(nkStrLit, origname))
        else:
          # {.impnameC.} shortcut
          nimState.newPragma(node, nimState.impShort & "C")

    # Need {.convention.} and {.header.} if applicable
    if name != origname:
      if nimState.includeHeader():
        # {.impnameHC.} shortcut
        nimState.addPragma(node, prident, nimState.impShort & "HC")
      else:
        # {.convention.}
        nimState.addPragma(node, prident, nimState.gState.convention)

        if nimState.gState.dynlib.nBl:
          # {.dynlib.} for DLLs
          nimState.addPragma(node, prident, "dynlib", nimState.getIdent(nimState.gState.dynlib))

    procDef.add prident
    procDef.add newNode(nkEmpty)
    procDef.add newNode(nkEmpty)

    # nkProcSection.add
    nimState.procSection.add procDef

    nimState.printDebug(procDef)

proc addDecl(nimState: NimState, node: TSNode) =
  # Add a declaration
  decho("addDecl()")
  nimState.printDebug(node)

  let
    start = getStartAtom(node)

  for i in start+1 ..< node.len:
    if not node[i].firstChildInTree("function_declarator").isNil:
      # Proc declaration - var or actual proc
      if node[i].getAtom().getPxName(1) == "pointer_declarator":
        # proc var
        nimState.addProcVar(node[i], node[start])
      else:
        # proc
        nimState.addProc(node[i], node[start])
    else:
      # Regular var
      discard

proc processNode(nimState: NimState, node: TSNode): bool =
  result = true

  case node.getName()
  of "preproc_def":
    nimState.addConst(node)
  of "type_definition":
    if node.len > 0 and node[0].getName() == "enum_specifier":
      nimState.addEnum(node)
    elif node.len > 0 and node[0].getName() == "union_specifier":
      nimState.addType(node, union = true)
    else:
      nimState.addType(node)
  of "struct_specifier":
    nimState.addType(node)
  of "union_specifier":
    nimState.addType(node, union = true)
  of "enum_specifier":
    nimState.addEnum(node)
  of "declaration":
    nimState.addDecl(node)
  else:
    # Unknown
    result = false

proc searchTree(nimState: NimState, root: TSNode) =
  # Search AST generated by tree-sitter for recognized elements
  var
    node = root
    nextnode: TSNode
    depth = 0
    processed = false

  while true:
    if not node.isNil() and depth > -1:
      processed = nimState.processNode(node)
    else:
      break

    if not processed and node.len() != 0:
      nextnode = node[0]
      depth += 1
    else:
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.isNil():
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if depth == -1:
          break
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().isNil():
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc setupPragmas(nimState: NimState, root: TSNode, fullpath: string) =
  # Create shortcut pragmas to reduce clutter
  var
    hdrPragma: PNode
    hdrConvPragma: PNode
    impPragma = newNode(nkPragma)
    impConvPragma = newNode(nkPragma)

  # {.pragma: impname, importc.}
  nimState.addPragma(root, impPragma, "pragma", nimState.getIdent(nimState.impShort))
  nimState.addPragma(root, impPragma, "importc")

  if nimState.includeHeader():
    # Path to header const
    nimState.constSection.add nimState.newConstDef(
      root, fname = nimState.currentHeader, fval = '"' & fullpath & '"')

    # {.pragma: impnameH, header: "xxx".} for types when name != origname
    hdrPragma = nimState.newPragma(root, "pragma", nimState.getIdent(nimState.impShort & "H"))
    nimState.addPragma(root, hdrPragma, "header", nimState.getIdent(nimState.currentHeader))

    # Add {.impnameH.} to {.impname.}
    nimState.addPragma(root, impPragma, nimState.impShort & "H")

    # {.pragma: impnameHC, impnameH, convention.} for procs when name != origname
    hdrConvPragma = nimState.newPragma(root, "pragma", nimState.getIdent(nimState.impShort & "HC"))
    nimState.addPragma(root, hdrConvPragma, nimState.impShort & "H")
    nimState.addPragma(root, hdrConvPragma, nimState.gState.convention)

  # {.pragma: impnameC, impname, convention.} for procs
  nimState.addPragma(root, impConvPragma, "pragma", nimState.getIdent(nimState.impShort & "C"))
  nimState.addPragma(root, impConvPragma, nimState.impShort)
  nimState.addPragma(root, impConvPragma, nimState.gState.convention)

  if nimState.gState.dynlib.nBl:
    # {.dynlib.} for DLLs
    nimState.addPragma(root, impConvPragma, "dynlib", nimState.getIdent(nimState.gState.dynlib))

  # Add all pragma shortcuts to output
  if not hdrPragma.isNil:
    nimState.pragmaSection.add hdrPragma
    nimState.pragmaSection.add hdrConvPragma
  nimState.pragmaSection.add impPragma
  nimState.pragmaSection.add impConvPragma

proc printNimHeader*(gState: State) =
  # Top level output with context info
  gecho """# Generated at $1
# Command line:
#   $2 $3

{.hint[ConvFromXtoItselfNotNeeded]: off.}

import nimterop/types
""" % [$now(), getAppFilename(), commandLineParams().join(" ")]

proc printNim*(gState: State, fullpath: string, root: TSNode) =
  # Generate Nim from tree-sitter AST root node
  let
    nimState = new(NimState)
    fp = fullpath.replace("\\", "/")

  # Track identifiers already rendered and corresponding PNodes
  nimState.identifiers = newTable[string, string]()
  nimState.identifierNodes = newTable[string, PNode]()

  # toast objects
  nimState.gState = gState
  nimState.currentHeader = getCurrentHeader(fullpath)
  nimState.impShort = nimState.currentHeader.replace("header", "imp")
  nimState.sourceFile = fullpath

  # Nim compiler objects
  nimState.identCache = newIdentCache()
  nimState.config = newConfigRef()
  nimstate.graph = newModuleGraph(nimState.identCache, nimState.config)

  # Initialize all section PNodes
  nimState.constSection = newNode(nkConstSection)
  nimState.enumSection = newNode(nkStmtList)
  nimState.pragmaSection = newNode(nkStmtList)
  nimState.procSection = newNode(nkStmtList)
  nimState.typeSection = newNode(nkTypeSection)
  nimState.varSection = newNode(nkVarSection)

  # Setup pragmas
  nimState.setupPragmas(root, fp)

  # Search root node and render Nim
  nimState.searchTree(root)

  # Add any unused cOverride symbols to output
  nimState.addAllOverrideFinal()

  # Create output to Nim using Nim compiler renderer
  var
    tree = newNode(nkStmtList)
  tree.add nimState.enumSection
  tree.add nimState.constSection
  tree.add nimState.pragmaSection
  tree.add nimState.typeSection
  tree.add nimState.varSection
  tree.add nimState.procSection

  gecho tree.renderTree()
