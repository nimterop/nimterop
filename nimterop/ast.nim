import macros, os, strformat

import regex

import getters, globals

proc addReorder*(): NimNode =
  result = newNimNode(nnkStmtList)
  if not gReorder:
    gReorder = true
    result.add parseStmt(
      "{.experimental: \"codeReordering\".}"
    )

proc addHeader*(fullpath: string) =
  gCurrentHeader = ("header" & fullpath.splitFile().name.replace(re"[-.]+", ""))
  gConstStr &= &"  {gCurrentHeader} = \"{fullpath}\" # addHeader()\n"

#
# Preprocessor
#
  
proc preprocDef(node: ref Ast) =
  if node.children.len() == 2:
    let
      name = getNodeValIf(node.children[0], "identifier")
      val = getNodeValIf(node.children[1], "preproc_arg")

    if name.nBl and val.nBl and name notin gConsts:
      gConsts.add(name)
      if val.getLit().nBl:
        # #define NAME VALUE
        gConstStr &= &"  {name.getIdentifier()}* = {val} # preprocDef()\n"

#
# Types
#

proc typeScan(node: ref Ast, sym, identifier, offset: string): string =
  if node.sym != sym or node.children.len() != 2:
    return

  let
    pname = getNodeValIf(node.children[1], identifier)
    ptyp = getNodeValIf(node.children[0], "primitive_type")
    ttyp = getNodeValIf(node.children[0], "type_identifier")
  
  if pname.len() == 0:
    return
  elif ptyp.nBl:
    result = &"{offset}{pname.getIdentifier()}: {ptyp.getType()}"
  elif ttyp.nBl:
    result = &"{offset}{pname.getIdentifier()}: {ttyp}"
  elif node.children[0].sym in ["struct_specifier", "enum_specifier"] and node.children[0].children.len() == 1:
    let styp = getNodeValIf(node.children[0].children[0], "type_identifier")
    if styp.nBl:
      result = &"{offset}{pname.getIdentifier()}: {styp}"
  else:
    return

proc structSpecifier(node: ref Ast, name = "") =
  var stmt: string
  if node.children.len() == 1 and name notin gTypes:
    case node.children[0].sym:
      of "type_identifier":
        let typ = getNodeValIf(node.children[0], "type_identifier")
        if typ.nBl:
          gTypes.add(name)
          if name != typ:
            # typedef struct X Y
            gTypeStr &= &"  {name}* = {typ} #1 structSpecifier()\n"
          else:
            # typedef struct X X
            gTypeStr &= &"  {name}* {{.importc: \"{name}\", header: {gCurrentHeader}, bycopy.}} = object #2 structSpecifier()\n"

      of "field_declaration_list":
        # typedef struct { fields } X
        stmt = &"  {name}* {{.importc: \"{name}\", header: {gCurrentHeader}, bycopy.}} = object #3 structSpecifier()\n"
          
        for field in node.children[0].children:
          let ts = typeScan(field, "field_declaration", "field_identifier", "    ")
          if ts.len() == 0:
            return
          stmt &= ts & "\n"
        
        gTypes.add(name)
        gTypeStr &= stmt
  elif name.len() == 0 and node.children.len() == 2 and node.children[1].sym == "field_declaration_list":
    let ename = getNodeValIf(node.children[0], "type_identifier")
    if ename.nBl and ename notin gTypes:
      # struct X { fields }
      stmt &= &"  {ename}* {{.importc: \"struct {ename}\", header: {gCurrentHeader}, bycopy.}} = object #4 structSpecifier()\n"

      for field in node.children[1].children:
        let ts = typeScan(field, "field_declaration", "field_identifier", "    ")
        if ts.len() == 0:
          return
        stmt &= ts & "\n"

      gTypes.add(name)
      gTypeStr &= stmt

proc enumSpecifier(node: ref Ast, name = "") =
  var
    ename: string
    elid: int
    stmt: string
    
  if node.children.len() == 1 and node.children[0].sym == "enumerator_list":
    # typedef enum { fields } X
    ename = name
    elid = 0
    stmt = &"  {name}* = enum #1 enumSpecifier()\n"
  elif name.len() == 0 and node.children.len() == 2 and node.children[1].sym == "enumerator_list":
    ename = getNodeValIf(node.children[0], "type_identifier")
    elid = 1
    if ename.nBl:
      # enum X { fields }
      stmt = &"  {ename}* = enum #2 enumSpecifier()\n"
    else:
      return

  for field in node.children[elid].children:
    if field.sym == "enumerator":
      let fname = getNodeValIf(field.children[0], "identifier")
      if field.children.len() == 1:
        stmt &= &"    {fname}\n"
      elif field.children.len() == 2 and field.children[1].sym == "number_literal":
        let num = getNodeValIf(field.children[1], "number_literal")
        stmt &= &"    {fname} = {num}\n"
      else:
        return
  
  if ename notin gTypes:
    gTypes.add(name)
    gTypeStr &= stmt

proc typeDefinition(node: ref Ast) =
  if node.children.len() == 2:
    let
      name = getNodeValIf(node.children[1], "type_identifier")
      ptyp = getNodeValIf(node.children[0], "primitive_type")
      ttyp = getNodeValIf(node.children[0], "type_identifier")
  
    if name.nBl and name notin gTypes:
      if ptyp.nBl:
        # typedef int X
        gTypes.add(name)
        gTypeStr &= &"  {name}* = {ptyp.getType()} #1 typeDefinition()\n"
      elif ttyp.nBl:
        # typedef X Y
        gTypes.add(name)
        gTypeStr &= &"  {name}* = {ttyp} #2 typeDefinition()\n"
      else:
        case node.children[0].sym:
          of "struct_specifier":
            structSpecifier(node.children[0], name)
          of "enum_specifier":
            enumSpecifier(node.children[0], name)

proc functionDeclarator(node: ref Ast, typ: string) =
  if node.children.len() == 2:
    let
      name = getNodeValIf(node.children[0], "identifier")
    
    if name.nBl and name notin gProcs and node.children[1].sym == "parameter_list":
      # typ function(typ param1, ...)
      var stmt = &"# functionDeclarator()\nproc {name}*("
        
      for i in 0 .. node.children[1].children.len()-1:
        let ts = typeScan(node.children[1].children[i], "parameter_declaration", "identifier", "")
        if ts.len() == 0:
          return
        stmt &= ts
        if i != node.children[1].children.len()-1:
          stmt &= ", "
      
      if typ != "void":
        stmt &= &"): {typ.getType()} "
      else:
        stmt &= ") "
      
      stmt &= &"{{.importc: \"{name}\", header: {gCurrentHeader}.}}\n"

      gProcs.add(name)
      gProcStr &= stmt
      
proc declaration*(node: ref Ast) =
  if node.children.len() == 2 and node.children[1].sym == "function_declarator":
    let
      ptyp = getNodeValIf(node.children[0], "primitive_type")
      ttyp = getNodeValIf(node.children[0], "type_identifier")

    if ptyp.nBl:
      functionDeclarator(node.children[1], ptyp.getType())
    elif ttyp.nBl:
      functionDeclarator(node.children[1], ttyp)
    elif node.children[0].sym == "struct_specifier" and node.children[0].children.len() == 1:
      let styp = getNodeValIf(node.children[0].children[0], "type_identifier")
      if styp.nBl:
        functionDeclarator(node.children[1], styp)
          
proc genNimAst*(node: ref Ast) =
  case node.sym:
    of "ERROR":
      let (line, col) = getLineCol(node)
      echo &"Potentially invalid syntax at line {line} column {col}"
    of "preproc_def":
      preprocDef(node)
    of "type_definition":
      typeDefinition(node)
    of "declaration":
      declaration(node)
    of "struct_specifier":
      if node.parent.sym notin ["type_definition", "declaration"]:
        structSpecifier(node)
    of "enum_specifier":
      if node.parent.sym notin ["type_definition", "declaration"]:
        enumSpecifier(node)
    of "":
      return

  for child in node.children:
    genNimAst(child)
