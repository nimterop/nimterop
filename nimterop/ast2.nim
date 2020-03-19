import macros, os, sets, strformat, strutils, tables, times

import regex

import compiler/[ast, idents, modulegraphs, options, parser, renderer]

import "."/treesitter/api

import "."/[globals, getters]

# Move to getters after ast2 becomes default

proc getPtrType*(str: string): string =
  result = case str:
    of "cchar":
      "cstring"
    of "object":
      "pointer"
    else:
      str

proc parseString(nimState: NimState, str: string): PNode =
  result = parseString(str, nimState.identCache, nimState.config)

proc getLit*(nimState: NimState, str: string): PNode =
  # Used to convert #define literals into const and expressions
  # in array sizes
  let
    str = str.replace(re"/[/*].*?(?:\*/)?$", "").strip()

  if str.contains(re"^[\-]?[\d]+$"):              # decimal
    result = newIntNode(nkIntLit, parseInt(str))

  elif str.contains(re"^[\-]?[\d]*[.]?[\d]+$"):   # float
    result = newFloatNode(nkFloatLit, parseFloat(str))

  # # TODO - hex becomes int on render
  # elif str.contains(re"^0x[\da-fA-F]+$"):         # hexadecimal
  #   result = newIntNode(nkIntLit, parseHexInt(str))

  elif str.contains(re"^'[[:ascii:]]'$"):         # char
    result = newNode(nkCharLit)
    result.intVal = str[1].int64

  elif str.contains(re"""^"[[:ascii:]]+"$"""):    # char *
    result = newStrNode(nkStrLit, str[1 .. ^2])

  else:
    result = nimState.parseString(nimState.getNimExpression(str))
    if result.isNil:
      result = newNode(nkNilLit)

proc getOverrideOrSkip(nimState: NimState, node: TSNode, origname: string, kind: NimSymKind): PNode =
  let
    override = nimState.getOverride(origname, kind)
    def =
      if kind == nskConst:
        nkConstDef
      elif kind == nskType:
        nkTypeDef
      else:
        nkEmpty
    skind =
      if kind == nskConst:
        "const "
      elif kind == nskType:
        "type "
      else:
        ""
  if override.nBl:
    result = newNode(def)
    result.add nimState.parseString(nimState.getComments())
    result.add nimState.parseString(skind & override)[0]
  else:
    result = nimState.parseString(nimState.getComments())
    result.add nimState.parseString(&"  # $1'{origname}' skipped" % skind)
    if nimState.gState.debug:
      nimState.skipStr &= &"\n{nimState.getNodeVal(node)}"

proc newConstDef(nimState: NimState, node: TSNode, fname = "", fval = ""): PNode =
  let
    # node[0] = identifier = const name
    (name, origname, info) = nimState.getNameInfo(node.getAtom(), nskConst)
    
    ident =
      if fname.nBl:
        nimState.getIdent(fname, info)
      else:
        nimState.getIdent(name, info)

    # node[1] = preproc_arg = value
    val =
      if fval.nBl:
        newStrNode(nkStrLit, fval)
      else:
        nimState.getLit(nimState.getNodeVal(node[1]))

  if name.Bl and fname.Bl:
    # Name skipped or overridden since blank
    result = nimState.getOverrideOrSkip(node, origname, nskConst)
  elif val.kind != nkNilLit and nimState.addNewIdentifer(name):
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
    result.add val

proc addConst(nimState: NimState, node: TSNode) =
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

proc addPragma(nimState: NimState, node: TSNode, pragma: PNode, pragmas: OrderedTable[string, PNode]) =
  # Add pragmas to an existing nkPragma tree
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

proc newPragma(nimState: NimState, node: TSNode, pragmas: OrderedTable[string, PNode]): PNode =
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

proc newPragmaExpr(nimState: NimState, node: TSNode, ident: PNode, pragmas: OrderedTable[string, PNode]): PNode =
  # Create nkPragmaExpr tree for multiple name:value
  result = newNode(nkPragmaExpr)
  result.add ident
  result.add nimState.newPragma(node, pragmas)

proc newTypeIdent(nimState: NimState, node: TSNode, fname = "", union = false): PNode =
  # Create nkTypeDef PNode with first ident
  #
  # If `fname`, use it instead of node.getAtom() for name
  let
    (name, origname, info) = nimState.getNameInfo(node.getAtom(), nskType)

    ident =
      if fname.nBl:
        nimState.getIdent(fname, info)
      else:
        nimState.getIdent(name, info)

    prident =
      if union:
        nimState.newPragmaExpr(node, ident, "union")
      else:
        ident

  if name.Bl and fname.Bl:
    # Name skipped or overridden since blank
    result = nimState.getOverrideOrSkip(node, origname, nskType)
  else:
    # type name* =
    #
    # nkTypeDef(
    #  nkPostfix(
    #   nkIdent("*"),
    #   nkIdent(name)
    #  ),
    #  nkEmpty()
    # )
    result = newNode(nkTypeDef)
    result.add prident
    result.add newNode(nkEmpty)

proc newPtrTree(nimState: NimState, count: int, typ: PNode): PNode =
  # Create nkPtrTy tree depending on count
  #
  # Reduce by 1 if Nim type available for ptr X - e.g. ptr cchar = cstring
  var
    count = count
    chng = false
  if typ.kind == nkIdent:
    let
      tname = typ.ident.s
      ptname = getPtrType(tname)
    if tname != ptname:
      # If Nim type available, use that ident
      result = nimState.getIdent(ptname, typ.info, exported = false)
      chng = true
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
    result = newNode(nkPtrTy)
    var
      parent = result
      child: PNode
    for i in 1 ..< count:
      child = newNode(nkPtrTy)
      parent.add child
      parent = child
    parent.add typ
  elif not chng:
    # Either no ptr, or none left after Nim type adjustment
    result = typ

proc newArrayTree(nimState: NimState, node: TSNode, typ, size: PNode): PNode =
  # Create nkBracketExpr tree depending on input
  let
    info = nimState.getLineInfo(node.getAtom())
    ident = nimState.getIdent("array", info, exported = false)

  # array[size, typ]
  #
  # nkBracketExpr(
  #  nkIdent("array"),
  #  size,
  #  typ
  # )
  result = newNode(nkBracketExpr)
  result.add ident
  result.add size
  result.add typ

proc getTypeArray(nimState: NimState, node: TSNode): PNode
proc getTypeProc(nimState: NimState, name: string, node: TSNode): PNode

proc newIdentDefs(nimState: NimState, name: string, node: TSNode, offset: SomeInteger, exported = false): PNode =
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
  result = newNode(nkIdentDefs)

  let
    start = getStartAtom(node)

    # node[start] - param type
    (tname, _, tinfo) = nimState.getNameInfo(node[start].getAtom(), nskType, parent = name)
    tident = nimState.getIdent(tname, tinfo, exported = false)

  if start == node.len - 1:
    # Only for proc with no named param - create a param name based on offset
    #
    # int func(char, int);
    let
      pname = "a" & $(offset+1)
      pident = nimState.getIdent(pname, tinfo, exported)
    result.add pident
    result.add tident
    result.add newNode(nkEmpty)
  else:
    let
      fdecl = node[start+1].anyChildInTree("function_declarator")
      adecl = node[start+1].anyChildInTree("array_declarator")
      abst = node[start+1].getName() == "abstract_pointer_declarator"
    if fdecl.isNil and adecl.isNil:
      if abst:
        # Only for proc with no named param with pointer type
        # Create a param name based on offset
        #
        # int func(char *, int **);
        let
          pname = "a" & $(offset+1)
          pident = nimState.getIdent(pname, tinfo, exported)
          acount = node[start+1].getXCount("abstract_pointer_declarator")
        result.add pident
        result.add nimState.newPtrTree(acount, tident)
        result.add newNode(nkEmpty)
      else:
        # Named param, simple type
        let
          (pname, _, pinfo) = nimState.getNameInfo(node[start+1].getAtom(), nskField, parent = name)
          pident = nimState.getIdent(pname, pinfo, exported)

          count = node[start+1].getPtrCount()
        result.add pident
        if count > 0:
          result.add nimState.newPtrTree(count, tident)
        else:
          result.add tident
        result.add newNode(nkEmpty)
    elif not fdecl.isNil:
      # Named param, function pointer
      let
        (pname, _, pinfo) = nimState.getNameInfo(node[start+1].getAtom(), nskField, parent = name)
        pident = nimState.getIdent(pname, pinfo, exported)
      result.add pident
      result.add nimState.getTypeProc(name, node)
      result.add newNode(nkEmpty)
    elif not adecl.isNil:
      # Named param, array type
      let
        (pname, _, pinfo) = nimState.getNameInfo(node[start+1].getAtom(), nskField, parent = name)
        pident = nimState.getIdent(pname, pinfo, exported)
      result.add pident
      result.add nimState.getTypeArray(node)
      result.add newNode(nkEmpty)
    else:
      result = nil

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
      # Add nkIdentDefs for each param
      let
        param = nimState.newIdentDefs(name, node[i], i, exported = false)
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
  #  nkEmpty()
  # )
  result = newNode(nkProcTy)
  result.add nimState.newFormalParams(name, node, rtyp)
  result.add newNode(nkEmpty)

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
      # Add nkIdentDefs for each field
      let
        field = nimState.newIdentDefs(name, node[i], i, exported = true)
      if not field.isNil:
        result.add field

proc addTypeObject(nimState: NimState, node: TSNode, fname = "", duplicate = "", union = false) =
  # Add a type of object
  #
  # If `fname` is set, use it as the name
  # If `duplicate` is set, don't add the same name
  decho("addTypeObject()")
  let
    typeDef = nimState.newTypeIdent(node, fname, union = union)
    name = $typeDef[0][1]

  if name != duplicate:
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
    let
      obj = newNode(nkObjectTy)
    obj.add newNode(nkEmpty)
    obj.add newNode(nkEmpty)

    let
      fdlist = node.anyChildInTree("field_declaration_list")
    if not fdlist.isNil and fdlist.len > 0:
      # Add fields to object if present
      obj.add nimState.newRecListTree(name, fdlist)
    else:
      obj.add newNode(nkEmpty)

    typeDef.add obj

    # nkTypeSection.add
    nimState.typeSection.add typeDef

    nimState.printDebug(typeDef)

proc addTypeTyped(nimState: NimState, node: TSNode, ftname = "", duplicate = "") =
  # Add a type of a specified type
  #
  # If `ftname` is set, use it as the type name
  # If `duplicate` is set, don't add the same name
  decho("addTypeTyped()")
  let
    start = getStartAtom(node)
  for i in start+1 ..< node.len:
    # Add a type of a specific type
    let
      # node[i] = identifer = name
      typeDef = nimState.newTypeIdent(node[i])
      name = $typeDef[0][1]

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
    if $typeDef[0][1] != tname:
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
      nimState.addTypeObject(node, duplicate = duplicate)

proc getTypeArray(nimState: NimState, node: TSNode): PNode =
  # Create array type tree
  let
    start = getStartAtom(node)

    # node[start] = identifier = type name
    (name, origname, info) = nimState.getNameInfo(node[start].getAtom(), nskType)
    ident = nimState.getIdent(name, info, exported = false)

    # Top-most array declarator
    adecl = node[start+1].firstChildInTree("array_declarator")

    # node[start+1] could have nested arrays
    acount = adecl.getArrayCount()
    innermost = adecl.mostNestedChildInTree()

    # node[start+1] could have nested pointers - type
    tcount = node[start+1].getPtrCount()

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
    let
      size = nimState.getLit(nimState.getNodeVal(cnode[1]))
    if size.kind != nkNilLit:
      result = nimState.newArrayTree(cnode, result, size)
      cnode = cnode[0]

  if ncount > 0:
    result = nimState.newPtrTree(ncount, result)

proc addTypeArray(nimState: NimState, node: TSNode) =
  # Add a type of array type
  decho("addTypeArray()")
  let
    # node[1] = identifer = name
    typeDef = nimState.newTypeIdent(node[1])

    typ = nimState.getTypeArray(node)

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

proc getTypeProc(nimState: NimState, name: string, node: TSNode): PNode =
  # Create proc type tree
  let
    # node[0] = identifier = return type name
    (rname, _, rinfo) = nimState.getNameInfo(node[0].getAtom(), nskType, parent = name)

    # Parameter list
    plist = node[1].anyChildInTree("parameter_list")

    # node[1] could have nested pointers
    tcount = node[1].getPtrCount()

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
    ncount = node[1].getAtom().tsNodeParent().getPtrCount(reverse = true)

  # Return type
  var
    retType = nimState.getIdent(rname, rinfo, exported = false)
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
    # node[1] = identifier = name
    typeDef = nimState.newTypeIdent(node[1])
    name = $typeDef[0][1]

    procTy = nimState.getTypeProc(name, node)

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
  #    nkEmpty()
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
              nimState.addTypeTyped(node, duplicate = nimState.getNodeVal(node[0].getAtom()))
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
            nimState.addTypeObject(node[0], fname = name, union = union)

            if name.nBl:
              # Add any additional names except duplicate
              nimState.addTypeTyped(node, ftname = name, duplicate = name)

proc addEnum(nimState: NimState, node: TSNode) =
  decho("addEnum()")
  nimState.printDebug(node)

proc addProc(nimState: NimState, node: TSNode) =
  # Add a proc
  decho("addProc()")
  nimState.printDebug(node)

  let
    start = getStartAtom(node)

    # node[start+1] = identifier = name
    ident = nimState.newTypeIdent(node[start+1])
    name = $ident[0][1]

    # node[start+1] could have nested pointers
    tcount = node[start+1].getPtrCount()

    # node[start] = identifier = return type name
    (rname, _, rinfo) = nimState.getNameInfo(node[start].getAtom(), nskType, parent = name)

    # Parameter list
    plist = node[start+1].anyChildInTree("parameter_list")

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
    retType = nimState.getIdent(rname, rinfo, exported = false)
  if tcount > 0:
    retType = nimState.newPtrTree(tcount, retType)

  # Proc with return type and params
  procDef.add nimState.newFormalParams(name, plist, retType)
  procDef.add newNode(nkEmpty) # Pragmas
  procDef.add newNode(nkEmpty)
  procDef.add newNode(nkEmpty)

  # nkProcSection.add
  nimState.procSection.add procDef

  nimState.printDebug(procDef)

proc processNode(nimState: NimState, node: TSNode): bool =
  result = true

  case node.getName()
  of "preproc_def":
    nimState.addConst(node)
  of "type_definition":
    if not node.firstChildInTree("enum_specifier").isNil():
      nimState.addEnum(node)
    elif not node.firstChildInTree("union_specifier").isNil():
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
    nimState.addProc(node)
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
  var
    impPragma = newNode(nkPragma)
    impCPragma = newNode(nkPragma)

  nimState.addPragma(root, impPragma, "pragma", nimState.getIdent(nimState.impShort))
  nimState.addPragma(root, impPragma, "importc")

  if nimState.includeHeader():
    nimState.constSection.add nimState.newConstDef(
      root, fname = nimState.currentHeader, fval = fullpath)

    nimState.addPragma(root, impPragma, "header", newStrNode(nkStrLit, nimState.currentHeader))

  nimState.addPragma(root, impCPragma, "pragma", nimState.getIdent(nimState.impShort & "C"))
  nimState.addPragma(root, impCPragma, nimState.impShort)
  nimState.addPragma(root, impCPragma, "cdecl")

  if nimState.gState.dynlib.nBl:
    nimState.addPragma(root, impCPragma, "dynlib", nimState.getIdent(nimState.gState.dynlib))

  nimState.pragmaSection.add impPragma
  nimState.pragmaSection.add impCPragma

proc printNimHeader*(gState: State) =
  gecho """# Generated at $1
# Command line:
#   $2 $3

{.hint[ConvFromXtoItselfNotNeeded]: off.}

import nimterop/types
""" % [$now(), getAppFilename(), commandLineParams().join(" ")]

proc printNim*(gState: State, fullpath: string, root: TSNode) =
  let
    nimState = new(NimState)
    fp = fullpath.replace("\\", "/")

  nimState.identifiers = newTable[string, string]()

  nimState.gState = gState
  nimState.currentHeader = getCurrentHeader(fullpath)
  nimState.impShort = nimState.currentHeader.replace("header", "imp")
  nimState.sourceFile = fullpath

  # Nim compiler objects
  nimState.identCache = newIdentCache()
  nimState.config = newConfigRef()
  nimstate.graph = newModuleGraph(nimState.identCache, nimState.config)

  nimState.pragmaSection = newNode(nkStmtList)
  nimState.constSection = newNode(nkConstSection)
  nimState.enumSection = newNode(nkStmtList)
  nimState.procSection = newNode(nkStmtList)
  nimState.typeSection = newNode(nkTypeSection)

  nimState.setupPragmas(root, fp)

  nimState.searchTree(root)

  var
    tree = newNode(nkStmtList)
  tree.add nimState.pragmaSection
  tree.add nimState.enumSection
  tree.add nimState.constSection
  tree.add nimState.typeSection
  tree.add nimState.procSection

  gecho tree.renderTree()
