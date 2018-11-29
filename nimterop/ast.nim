import macros, os, strformat, strutils

import treesitter/runtime

import getters, globals

#
# Preprocessor
#

proc pPreprocDef(node: TSNode) =
  if node.tsNodeNamedChildCount() == 2:
    let
      name = getNodeValIf(node.tsNodeNamedChild(0), "identifier")
      val = getNodeValIf(node.tsNodeNamedChild(1), "preproc_arg")

    if name.nBl and val.nBl and name notin gStateRT.consts:
      gStateRT.consts.add(name)
      if val.getLit().nBl:
        # #define NAME VALUE
        gStateRT.constStr &= &"  {name.getIdentifier()}* = {val}        # pPreprocDef()\n"

#
# Types
#

proc typeScan(node: TSNode, sym, id: string, offset: string): string =
  if node.tsNodeIsNull() or $node.tsNodeType() != sym or node.tsNodeNamedChildCount() != 2:
    return

  var
    name = getNodeValIf(node.tsNodeNamedChild(1), id)
    ptyp = getNodeValIf(node.tsNodeNamedChild(0), "primitive_type")
    ttyp = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")
    ptrname = false

  if name.len == 0 and $node.tsNodeNamedChild(1).tsNodeType() == "pointer_declarator" and node.tsNodeNamedChild(1).tsNodeNamedChildCount() == 1:
    name = getNodeValIf(node.tsNodeNamedChild(1).tsNodeNamedChild(0), id)
    ptrname = true

  if name.len == 0:
    return
  elif ptyp.nBl:
    ptyp = ptyp.getType()
    if ptyp != "object" and ptrname:
      ptyp = &"ptr {ptyp}"
    result = &"{offset}{name.getIdentifier()}: {ptyp}"
  elif ttyp.nBl:
    if ptrname:
      ttyp = &"ptr {ttyp}"
    result = &"{offset}{name.getIdentifier()}: {ttyp}"
  elif $node.tsNodeNamedChild(0).tsNodeType() in ["struct_specifier", "enum_specifier"] and node.tsNodeNamedChild(0).tsNodeNamedChildCount() == 1:
    var styp = getNodeValIf(node.tsNodeNamedChild(0).tsNodeNamedChild(0), "type_identifier")
    if styp.nBl:
      if ptrname:
        styp = &"ptr {styp}"
      result = &"{offset}{name.getIdentifier()}: {styp}"

proc pStructSpecifier(node: TSNode, name = "") =
  var stmt: string
  if node.tsNodeNamedChildCount() == 1 and name notin gStateRT.types:
    case $node.tsNodeNamedChild(0).tsNodeType():
      of "type_identifier":
        let typ = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")
        if typ.nBl:
          gStateRT.types.add(name)
          if name != typ:
            # typedef struct X Y
            gStateRT.typeStr &= &"  {name.getIdentifier()}* = {typ}        #1 pStructSpecifier()\n"
          else:
            # typedef struct X X
            gStateRT.typeStr &= &"  {name.getIdentifier()}* {{.importc: \"{name}\", header: {gStateRT.currentHeader}, bycopy.}} = object        #2 pStructSpecifier()\n"

      of "field_declaration_list":
        # typedef struct { fields } X
        stmt = &"  {name.getIdentifier()}* {{.importc: \"{name}\", header: {gStateRT.currentHeader}, bycopy.}} = object        #3 pStructSpecifier()\n"

        if node.tsNodeNamedChild(0).tsNodeNamedChildCount() != 0:
          for i in 0 .. node.tsNodeNamedChild(0).tsNodeNamedChildCount()-1:
            if $node.tsNodeNamedChild(0).tsNodeNamedChild(i).tsNodeType() == "comment":
              continue
            let ts = typeScan(node.tsNodeNamedChild(0).tsNodeNamedChild(i), "field_declaration", "field_identifier", "    ")
            if ts.len == 0:
              return
            stmt &= ts & "\n"

          gStateRT.types.add(name)
          gStateRT.typeStr &= stmt
      else:
        discard

  elif name.len == 0 and node.tsNodeNamedChildCount() == 2 and $node.tsNodeNamedChild(1).tsNodeType() == "field_declaration_list":
    let ename = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")
    if ename.nBl and ename notin gStateRT.types:
      # struct X { fields }
      stmt &= &"  {ename}* {{.importc: \"struct {ename}\", header: {gStateRT.currentHeader}, bycopy.}} = object        #4 pStructSpecifier()\n"

      if node.tsNodeNamedChild(1).tsNodeNamedChildCount() != 0:
        for i in 0 .. node.tsNodeNamedChild(1).tsNodeNamedChildCount()-1:
          if $node.tsNodeNamedChild(1).tsNodeNamedChild(i).tsNodeType() == "comment":
            continue
          let ts = typeScan(node.tsNodeNamedChild(1).tsNodeNamedChild(i), "field_declaration", "field_identifier", "    ")
          if ts.len == 0:
            return
          stmt &= ts & "\n"

        gStateRT.types.add(name)
        gStateRT.typeStr &= stmt

proc pEnumSpecifier(node: TSNode, name = "") =
  var
    ename: string
    elid: uint32
    stmt: string

  if node.tsNodeNamedChildCount() == 1 and $node.tsNodeNamedChild(0).tsNodeType() == "enumerator_list":
    # typedef enum { fields } X
    ename = name
    elid = 0
    stmt = &"  {name.getIdentifier()}* = enum        #1 pEnumSpecifier()\n"
  elif node.tsNodeNamedChildCount() == 2 and $node.tsNodeNamedChild(1).tsNodeType() == "enumerator_list":
    if name.len == 0:
      ename = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")
    else:
      ename = name
    elid = 1
    if ename.nBl:
      # enum X { fields }
      stmt = &"  {ename}* = enum        #2 pEnumSpecifier()\n"
    else:
      return
  else:
    return

  if node.tsNodeNamedChild(elid).tsNodeNamedChildCount() != 0:
    for i in 0 .. node.tsNodeNamedChild(elid).tsNodeNamedChildCount()-1:
      let field = node.tsNodeNamedChild(elid).tsNodeNamedChild(i)
      if $field.tsNodeType() == "comment":
        continue
      if not field.tsNodeIsNull() and $field.tsNodeType() == "enumerator":
        let fname = getNodeValIf(field.tsNodeNamedChild(0), "identifier")
        if field.tsNodeNamedChildCount() == 1:
          stmt &= &"    {fname}\n"
        elif field.tsNodeNamedChildCount() == 2 and $field.tsNodeNamedChild(1).tsNodeType() == "number_literal":
          let num = getNodeValIf(field.tsNodeNamedChild(1), "number_literal")
          stmt &= &"    {fname} = {num}\n"
        else:
          return

    if ename notin gStateRT.types:
      gStateRT.types.add(name)
      gStateRT.typeStr &= stmt

proc pTypeDefinition(node: TSNode) =
  if node.tsNodeNamedChildCount() == 2:
    var
      name = getNodeValIf(node.tsNodeNamedChild(1), "type_identifier")
      ptyp = getNodeValIf(node.tsNodeNamedChild(0), "primitive_type")
      ttyp = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")
      ptrname = false

    if name.len == 0 and $node.tsNodeNamedChild(1).tsNodeType() == "pointer_declarator" and node.tsNodeNamedChild(1).tsNodeNamedChildCount() == 1:
      name = getNodeValIf(node.tsNodeNamedChild(1).tsNodeNamedChild(0), "type_identifier")
      ptrname = true

    if name.nBl and name notin gStateRT.types:
      if ptyp.nBl:
        # typedef int X
        gStateRT.types.add(name)
        ptyp = ptyp.getType()
        if ptyp != "object" and ptrname:
          ptyp = &"ptr {ptyp}"
        gStateRT.typeStr &= &"  {name.getIdentifier()}* = {ptyp}        #1 pTypeDefinition()\n"
      elif ttyp.nBl:
        # typedef X Y
        gStateRT.types.add(name)
        if ptrname:
          ttyp = &"ptr {ttyp}"
        gStateRT.typeStr &= &"  {name.getIdentifier()}* = {ttyp}        #2 pTypeDefinition()\n"
      else:
        case $node.tsNodeNamedChild(0).tsNodeType():
          of "struct_specifier":
            pStructSpecifier(node.tsNodeNamedChild(0), name)
          of "enum_specifier":
            pEnumSpecifier(node.tsNodeNamedChild(0), name)
          else:
            discard

proc pFunctionDeclarator(node: TSNode, typ: string) =
  if node.tsNodeNamedChildCount() == 2:
    let
      name = getNodeValIf(node.tsNodeNamedChild(0), "identifier")

    if name.nBl and name notin gStateRT.procs and $node.tsNodeNamedChild(1).tsNodeType() == "parameter_list":
      # typ function(typ param1, ...)
      var stmt = &"# pFunctionDeclarator()\nproc {name.getIdentifier()}*("

      if node.tsNodeNamedChild(1).tsNodeNamedChildCount() != 0:
        for i in 0 .. node.tsNodeNamedChild(1).tsNodeNamedChildCount()-1:
          let ts = typeScan(node.tsNodeNamedChild(1).tsNodeNamedChild(i), "parameter_declaration", "identifier", "")
          if ts.len == 0:
            return
          stmt &= ts
          if i != node.tsNodeNamedChild(1).tsNodeNamedChildCount()-1:
            stmt &= ", "

      if typ != "void":
        stmt &= &"): {typ.getType()} "
      else:
        stmt &= ") "

      stmt &= &"{{.importc: \"{name}\", header: {gStateRT.currentHeader}.}}\n"

      gStateRT.procs.add(name)
      gStateRT.procStr &= stmt

proc pDeclaration*(node: TSNode) =
  if node.tsNodeNamedChildCount() == 2 and $node.tsNodeNamedChild(1).tsNodeType() == "function_declarator":
    let
      ptyp = getNodeValIf(node.tsNodeNamedChild(0), "primitive_type")
      ttyp = getNodeValIf(node.tsNodeNamedChild(0), "type_identifier")

    if ptyp.nBl:
      pFunctionDeclarator(node.tsNodeNamedChild(1), ptyp.getType())
    elif ttyp.nBl:
      pFunctionDeclarator(node.tsNodeNamedChild(1), ttyp)
    elif $node.tsNodeNamedChild(0).tsNodeType() == "struct_specifier" and node.tsNodeNamedChild(0).tsNodeNamedChildCount() == 1:
      let styp = getNodeValIf(node.tsNodeNamedChild(0).tsNodeNamedChild(0), "type_identifier")
      if styp.nBl:
        pFunctionDeclarator(node.tsNodeNamedChild(1), styp)

proc genNimAst(root: TSNode) =
  var
    node = root
    nextnode: TSNode

  while true:
    if not node.tsNodeIsNull():
      case $node.tsNodeType():
        of "ERROR":
          let (line, col) = getLineCol(node)
          let file = gStateRT.sourceFile
          echo &"# [toast] Potentially invalid syntax at {file}:{line}:{col}"
        of "preproc_def":
          pPreprocDef(node)
        of "type_definition":
          pTypeDefinition(node)
        of "declaration":
          pDeclaration(node)
        of "struct_specifier":
          if $node.tsNodeParent().tsNodeType() notin ["type_definition", "declaration"]:
            pStructSpecifier(node)
        of "enum_specifier":
          if $node.tsNodeParent.tsNodeType() notin ["type_definition", "declaration"]:
            pEnumSpecifier(node)
        else:
          # TODO: log
          discard
    else:
      return

    if node.tsNodeNamedChildCount() != 0:
      nextnode = node.tsNodeNamedChild(0)
    else:
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.tsNodeIsNull():
      while true:
        node = node.tsNodeParent()
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().tsNodeIsNull():
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc printNim*(fullpath: string, root: TSNode) =
  echo "{.experimental: \"codeReordering\".}"

  var fp = fullpath.replace("\\", "/")
  gStateRT.currentHeader = getCurrentHeader(fullpath)
  gStateRT.constStr &= &"  {gStateRT.currentHeader} = \"{fp}\"\n"

  genNimAst(root)

  if gStateRT.constStr.nBl:
    echo "const\n" & gStateRT.constStr

  if gStateRT.typeStr.nBl:
    echo "type\n" & gStateRT.typeStr

  if gStateRT.procStr.nBl:
    echo gStateRT.procStr
