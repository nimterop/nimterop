import os, sequtils, sets, strformat, strutils, tables, times

import regex

import "."/[getters, globals, grammar, treesitter/api]

proc saveNodeData(node: TSNode, nimState: NimState): bool =
  let name = $node.tsNodeType()
  if name in gAtoms:
    var
      val = node.getNodeVal()

    if name == "primitive_type" and node.tsNodeParent.tsNodeType() == "sized_type_specifier":
      return true

    if name in ["number_literal", "identifier"] and $node.tsNodeParent.tsNodeType() in gExpressions:
      return true

    if name in ["primitive_type", "sized_type_specifier"]:
      val = val.getType()

    let
      pname = node.getPxName(1)
      ppname = node.getPxName(2)
      pppname = node.getPxName(3)
      ppppname = node.getPxName(4)

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

    if node.tsNodeType() == "field_identifier" and
      pname == "pointer_declarator" and
      ppname == "function_declarator":
      if pppname == "pointer_declarator":
        nimState.data.insert(("pointer_declarator", ""), nimState.data.len-1)
        if ppppname == "pointer_declarator":
          nimState.data.insert(("pointer_declarator", ""), nimState.data.len-1)
      nimState.data.add(("function_declarator", ""))

  elif name in gExpressions:
    if $node.tsNodeParent.tsNodeType() notin gExpressions:
      nimState.data.add((name, node.getNodeVal()))

  elif name in ["abstract_pointer_declarator", "enumerator", "field_declaration", "function_declarator"]:
    nimState.data.add((name.replace("abstract_", ""), ""))

  return true

proc searchAstForNode(ast: ref Ast, node: TSNode, nimState: NimState): bool =
  let
    childNames = node.getTSNodeNamedChildNames().join()

  if ast.isNil:
    return

  if ast.children.len != 0:
    if childNames.contains(ast.regex) or
      (childNames.len == 0 and ast.recursive):
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
          return node.saveNodeData(nimState)
      else:
        return node.saveNodeData(nimState)
  elif node.getTSNodeNamedChildCountSansComments() == 0:
    return node.saveNodeData(nimState)

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
          if searchAstForNode(ast, node, nimState):
            ast.tonim(ast, node, nimState)
            if gStateRT.debug:
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

proc printNimHeader*() =
  echo """# Generated at $1
# Command line:
#   $2 $3

{.experimental: "codeReordering".}
{.hint[ConvFromXtoItselfNotNeeded]: off.}

import nimterop/types
""" % [$now(), getAppFilename(), commandLineParams().join(" ")]

proc printNim*(fullpath: string, root: TSNode, astTable: AstTable) =
  var
    nimState = new(NimState)
    fp = fullpath.replace("\\", "/")
  nimState.identifiers = newTable[string, string]()

  nimState.currentHeader = getCurrentHeader(fullpath)
  nimState.constStr &= &"\n  {nimState.currentHeader} {{.used.}} = \"{fp}\""

  nimState.debug = gStateRT.debug

  root.searchAst(astTable, nimState)

  if nimState.enumStr.nBl:
    echo nimState.enumStr

  if nimState.constStr.nBl:
    echo &"const {nimState.constStr}\n"

  if nimState.typeStr.nBl:
    echo &"type {nimState.typeStr}\n"

  if nimState.procStr.nBl:
    echo &"{nimState.procStr}\n"

  if nimState.debugStr.nBl:
    echo nimState.debugStr
