import hashes, macros, os, sets, strformat, strutils, tables

import regex

import ".."/[globals, treesitter/api]
import "."/[getters, tshelp]

proc getHeaderPragma*(gState: State): string =
  result =
    if not gState.noHeader and gState.dynlib.Bl:
      &", header: {gState.currentHeader}"
    else:
      ""

proc getDynlib*(gState: State): string =
  result =
    if gState.dynlib.nBl:
      &", dynlib: {gState.dynlib}"
    else:
      ""

proc getImportC*(gState: State, origName, nimName: string): string =
  if nimName != origName:
    result = &"importc: \"{origName}\"{gState.getHeaderPragma()}"
  else:
    result = gState.impShort

proc getPragma*(gState: State, pragmas: varargs[string]): string =
  result = ""
  for pragma in pragmas.items():
    if pragma.nBl:
      result &= pragma & ", "
  if result.nBl:
    result = " {." & result[0 .. ^3] & ".}"

  result = result.replace(gState.impShort & ", cdecl", gState.impShort & "C")

  let
    dy = gState.getDynlib()

  if ", cdecl" in result and dy.nBl:
    result = result.replace(".}", dy & ".}")

proc saveNodeData(node: TSNode, gState: State): bool =
  let name = $node.tsNodeType()

  # Atoms are nodes whose values are to be saved
  if name in gAtoms:
    let
      pname = node.getPxName(1)
      ppname = node.getPxName(2)
      pppname = node.getPxName(3)
      ppppname = node.getPxName(4)

    var
      val = gState.getNodeVal(node)

    # Skip since value already obtained from parent atom
    if name == "primitive_type" and pname == "sized_type_specifier":
      return true

    # Skip since value already obtained from parent expression
    if name in ["number_literal", "identifier"] and pname in gExpressions:
      return true

    # Add reference point in saved data for bitfield_clause
    if name in ["number_literal"] and pname == "bitfield_clause":
      gState.data.add(("bitfield_clause", val))
      return true

    # Process value as a type
    if name in ["primitive_type", "sized_type_specifier"]:
      val = val.getType()

    if node.tsNodePrevNamedSibling().tsNodeIsNull():
      if pname == "pointer_declarator":
        if ppname notin ["function_declarator", "array_declarator"]:
          gState.data.add(("pointer_declarator", ""))
        elif ppname == "array_declarator":
          gState.data.add(("array_pointer_declarator", ""))

        # Double pointer
        if ppname == "pointer_declarator":
          gState.data.add(("pointer_declarator", ""))
      elif pname in ["function_declarator", "array_declarator"]:
        if ppname == "pointer_declarator":
          gState.data.add(("pointer_declarator", ""))
          if pppname == "pointer_declarator":
            gState.data.add(("pointer_declarator", ""))

    gState.data.add((name, val))

    if pname == "pointer_declarator" and
      ppname == "function_declarator":
      if name == "field_identifier":
        if pppname == "pointer_declarator":
          gState.data.insert(("pointer_declarator", ""), gState.data.len-1)
          if ppppname == "pointer_declarator":
            gState.data.insert(("pointer_declarator", ""), gState.data.len-1)
        gState.data.add(("function_declarator", ""))
      elif name == "identifier":
        gState.data.add(("pointer_declarator", ""))

  # Save node value for a top-level expression
  elif name in gExpressions and name != "escape_sequence":
    if $node.tsNodeParent.tsNodeType() notin gExpressions:
      gState.data.add((name, gState.getNodeVal(node)))

  elif name in ["abstract_pointer_declarator", "enumerator", "field_declaration", "function_declarator"]:
    gState.data.add((name.replace("abstract_", ""), ""))

  return true

proc searchAstForNode(ast: ref Ast, node: TSNode, gState: State): bool =
  let
    childNames = node.getTSNodeNamedChildNames().join()

  if ast.isNil:
    return

  if gState.debug:
    gState.nodeBranch.add $node.tsNodeType()
    gecho "#" & spaces(gState.nodeBranch.len * 2) & gState.nodeBranch[^1]

  if ast.children.nBl:
    if childNames.contains(ast.regex) or
      (childNames.Bl and ast.recursive):
      if node.getTSNodeNamedChildCountSansComments() != 0:
        var flag = true

        for i in 0 .. node.tsNodeNamedChildCount()-1:
          if $node.tsNodeNamedChild(i).tsNodeType() != "comment":
            let
              nodeChild = node.tsNodeNamedChild(i)
              astChild =
                if not ast.recursive:
                  ast.getAstChildByName($nodeChild.tsNodeType())
                else:
                  ast

            if not searchAstForNode(astChild, nodeChild, gState):
              flag = false
              break

        if flag:
          result = node.saveNodeData(gState)
      else:
        result = node.saveNodeData(gState)
    else:
      if gState.debug:
        gecho "#" & spaces(gState.nodeBranch.len * 2) & &"  {ast.getRegexForAstChildren()} !=~ {childNames}"
  elif node.getTSNodeNamedChildCountSansComments() == 0:
    result = node.saveNodeData(gState)

  if gState.debug:
    discard gState.nodeBranch.pop()
    if gState.nodeBranch.Bl:
      gecho ""

proc searchAst(root: TSNode, astTable: AstTable, gState: State) =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.tsNodeIsNull() and depth > -1:
      let
        name = $node.tsNodeType()
      if name in astTable:
        for ast in astTable[name]:
          if gState.debug:
            gecho "\n#  " & gState.getNodeVal(node).replace("\n", "\n#  ") & "\n"
          if searchAstForNode(ast, node, gState):
            ast.tonim(ast, node, gState)
            if gState.debug:
              gState.debugStr &= "\n# " & gState.data.join("\n# ") & "\n"
            break
        gState.data = @[]
    else:
      break

    if $node.tsNodeType() notin astTable and node.tsNodeNamedChildCount() != 0:
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.tsNodeIsNull():
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if depth == -1:
          break
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().tsNodeIsNull():
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc parseNim*(gState: State, fullpath: string, root: TSNode, astTable: AstTable) =
  # Generate Nim from tree-sitter AST root node
  var
    fp = fullpath.replace("\\", "/")

  gState.currentHeader = getCurrentHeader(fullpath)
  gState.impShort = gState.currentHeader.replace("header", "imp")
  gState.sourceFile = fullpath

  if not gState.noHeader and gState.dynlib.Bl:
    gState.constStr &= &"\n  {gState.currentHeader} {{.used.}} = \"{fp}\""

  root.searchAst(astTable, gState)

proc printNim*(gState: State) =
  # Print Nim generated by parseNim()
  if gState.enumStr.nBl:
    gecho &"{gState.enumStr}\n"

  gState.constStr = gState.getOverrideFinal(nskConst) & gState.constStr
  if gState.constStr.nBl:
    gecho &"const{gState.constStr}\n"

  gecho &"""
{{.pragma: {gState.impShort}, importc{gState.getHeaderPragma()}.}}
{{.pragma: {gState.impShort}C, {gState.impShort}, cdecl{gState.getDynlib()}.}}
"""

  gState.typeStr = gState.getOverrideFinal(nskType) & gState.typeStr
  if gState.typeStr.nBl:
    gecho &"type{gState.typeStr}\n"

  gState.procStr = gState.getOverrideFinal(nskProc) & gState.procStr
  if gState.procStr.nBl:
    gecho &"{gState.procStr}\n"

  gecho "{.pop.}"

  if gState.debug:
    if gState.debugStr.nBl:
      gecho gState.debugStr

    if gState.skipStr.nBl:
      let
        hash = gState.skipStr.hash().abs()
        sname = getTempDir() / &"nimterop_{$hash}.h"
      gecho &"# Writing skipped definitions to {sname}\n"
      writeFile(sname, gState.skipStr)
