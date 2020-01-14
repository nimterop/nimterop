import hashes, macros, os, sets, strformat, strutils, tables, times

import regex

import "."/[getters, globals, treesitter/api]

proc saveNodeData(node: TSNode, nimState: NimState): bool =
  let name = $node.tsNodeType()

  # Atoms are nodes whose values are to be saved
  if name in gAtoms:
    let
      pname = node.getPxName(1)
      ppname = node.getPxName(2)
      pppname = node.getPxName(3)
      ppppname = node.getPxName(4)

    var
      val = nimState.getNodeVal(node)

    # Skip since value already obtained from parent atom
    if name == "primitive_type" and pname == "sized_type_specifier":
      return true

    # Skip since value already obtained from parent expression
    if name in ["number_literal", "identifier"] and pname in gExpressions:
      return true

    # Add reference point in saved data for bitfield_clause
    if name in ["number_literal"] and pname == "bitfield_clause":
      nimState.data.add(("bitfield_clause", val))
      return true

    # Process value as a type
    if name in ["primitive_type", "sized_type_specifier"]:
      val = val.getType()

    if node.tsNodePrevNamedSibling().tsNodeIsNull():
      if pname == "pointer_declarator":
        if ppname notin ["function_declarator", "array_declarator"]:
          nimState.data.add(("pointer_declarator", ""))
        elif ppname == "array_declarator":
          nimState.data.add(("array_pointer_declarator", ""))

        # Double pointer
        if ppname == "pointer_declarator":
          nimState.data.add(("pointer_declarator", ""))
      elif pname in ["function_declarator", "array_declarator"]:
        if ppname == "pointer_declarator":
          nimState.data.add(("pointer_declarator", ""))
          if pppname == "pointer_declarator":
            nimState.data.add(("pointer_declarator", ""))

    nimState.data.add((name, val))

    if pname == "pointer_declarator" and
      ppname == "function_declarator":
      if name == "field_identifier":
        if pppname == "pointer_declarator":
          nimState.data.insert(("pointer_declarator", ""), nimState.data.len-1)
          if ppppname == "pointer_declarator":
            nimState.data.insert(("pointer_declarator", ""), nimState.data.len-1)
        nimState.data.add(("function_declarator", ""))
      elif name == "identifier":
        nimState.data.add(("pointer_declarator", ""))

  # Save node value for a top-level expression
  elif name in gExpressions and name != "escape_sequence":
    if $node.tsNodeParent.tsNodeType() notin gExpressions:
      nimState.data.add((name, nimState.getNodeVal(node)))

  elif name in ["abstract_pointer_declarator", "enumerator", "field_declaration", "function_declarator"]:
    nimState.data.add((name.replace("abstract_", ""), ""))

  return true

proc searchAstForNode(ast: ref Ast, node: TSNode, nimState: NimState): bool =
  let
    childNames = node.getTSNodeNamedChildNames().join()

  if ast.isNil:
    return

  if nimState.gState.debug:
    nimState.nodeBranch.add $node.tsNodeType()
    necho "#" & spaces(nimState.nodeBranch.len * 2) & nimState.nodeBranch[^1]

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

            if not searchAstForNode(astChild, nodeChild, nimState):
              flag = false
              break

        if flag:
          result = node.saveNodeData(nimState)
      else:
        result = node.saveNodeData(nimState)
    else:
      if nimState.gState.debug:
        necho "#" & spaces(nimState.nodeBranch.len * 2) & &"  {ast.getRegexForAstChildren()} !=~ {childNames}"
  elif node.getTSNodeNamedChildCountSansComments() == 0:
    result = node.saveNodeData(nimState)

  if nimState.gState.debug:
    discard nimState.nodeBranch.pop()
    if nimstate.nodeBranch.Bl:
      necho ""

proc searchAst(root: TSNode, astTable: AstTable, nimState: NimState) =
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
          if nimState.gState.debug:
            necho "\n#  " & nimState.getNodeVal(node).replace("\n", "\n#  ") & "\n"
          if searchAstForNode(ast, node, nimState):
            ast.tonim(ast, node, nimState)
            if nimState.gState.debug:
              nimState.debugStr &= "\n# " & nimState.data.join("\n# ") & "\n"
            break
        nimState.data = @[]
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

proc printNimHeader*(gState: State) =
  gecho """# Generated at $1
# Command line:
#   $2 $3

{.hint[ConvFromXtoItselfNotNeeded]: off.}

import nimterop/types
""" % [$now(), getAppFilename(), commandLineParams().join(" ")]

proc printNim*(gState: State, fullpath: string, root: TSNode, astTable: AstTable) =
  var
    nimState = new(NimState)
    fp = fullpath.replace("\\", "/")

  nimState.identifiers = newTable[string, string]()

  nimState.gState = gState
  nimState.currentHeader = getCurrentHeader(fullpath)
  nimState.impShort = nimState.currentHeader.replace("header", "imp")
  nimState.sourceFile = fullpath

  if nimState.gState.dynlib.Bl:
    nimState.constStr &= &"\n  {nimState.currentHeader} {{.used.}} = \"{fp}\""

  root.searchAst(astTable, nimState)

  if nimState.enumStr.nBl:
    necho &"{nimState.enumStr}\n"

  nimState.constStr = nimState.getOverrideFinal(nskConst) & nimState.constStr
  if nimState.constStr.nBl:
    necho &"const{nimState.constStr}\n"

  necho &"""
{{.pragma: {nimState.impShort}, importc{nimState.getHeader()}.}}
{{.pragma: {nimState.impShort}C, {nimState.impShort}, cdecl{nimState.getDynlib()}.}}
"""

  nimState.typeStr = nimState.getOverrideFinal(nskType) & nimState.typeStr
  if nimState.typeStr.nBl:
    necho &"type{nimState.typeStr}\n"

  nimState.procStr = nimState.getOverrideFinal(nskProc) & nimState.procStr
  if nimState.procStr.nBl:
    necho &"{nimState.procStr}\n"

  if nimState.gState.debug:
    if nimState.debugStr.nBl:
      necho nimState.debugStr

    if nimState.skipStr.nBl:
      let
        hash = nimState.skipStr.hash().abs()
        sname = getTempDir() / &"nimterop_{$hash}.h"
      necho &"# Writing skipped definitions to {sname}\n"
      writeFile(sname, nimState.skipStr)
