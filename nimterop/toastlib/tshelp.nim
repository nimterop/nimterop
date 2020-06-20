import sets, strformat, strutils

import ".."/treesitter/[api, c, cpp]
import ".."/globals
import "."/getters

template withCodeAst*(code: string, mode: string, body: untyped): untyped =
  ## A simple template to inject the TSNode into a body of code
  mixin treeSitterC
  mixin treeSitterCpp

  var parser = tsParserNew()
  defer:
    parser.tsParserDelete()

  doAssert code.nBl, "Empty code or preprocessor error"

  if mode == "c":
    doAssert parser.tsParserSetLanguage(treeSitterC()), "Failed to load C parser"
  elif mode == "cpp":
    doAssert parser.tsParserSetLanguage(treeSitterCpp()), "Failed to load C++ parser"
  else:
    doAssert false, "Invalid parser " & mode

  var
    tree = parser.tsParserParseString(nil, code.cstring, code.len.uint32)
    root {.inject.} = tree.tsTreeRootNode()

  body

  defer:
    tree.tsTreeDelete()

proc getCommented*(str: string): string =
  "\n# " & str.strip().replace("\n", "\n# ")

proc isNil*(node: TSNode): bool =
  node.tsNodeIsNull()

proc len*(node: TSNode): int =
  if not node.isNil:
    result = node.tsNodeNamedChildCount().int

proc `[]`*(node: TSNode, i: SomeInteger): TSNode =
  if i < type(i)(node.len()):
    result = node.tsNodeNamedChild(i.uint32)

proc getName*(node: TSNode): string {.inline.} =
  if not node.isNil:
    return $node.tsNodeType()

proc getNodeVal*(code: var string, node: TSNode): string =
  if not node.isNil:
    return code[node.tsNodeStartByte() .. node.tsNodeEndByte()-1]

proc getNodeVal*(gState: State, node: TSNode): string =
  gState.code.getNodeVal(node)

proc getAtom*(node: TSNode): TSNode =
  if not node.isNil:
    # Get child node which is topmost atom
    if node.getName() in gAtoms:
      return node
    elif node.len != 0:
      if node[0].getName() == "type_qualifier":
        # Skip const, volatile
        if node.len > 1:
          return node[1].getAtom()
        else:
          return
      else:
        return node[0].getAtom()

proc getStartAtom*(node: TSNode): int =
  if not node.isNil:
    # Skip const, volatile and other type qualifiers
    for i in 0 .. node.len - 1:
      if node[i].getAtom().getName() notin gAtoms:
        result += 1
      else:
        break

proc getConstQualifier*(gState: State, node: TSNode): bool =
  # Check if node siblings have type_qualifier = `const`
  var
    curr = node.tsNodePrevNamedSibling()
  while not curr.isNil:
    # Check previous siblings
    if curr.getName() == "type_qualifier" and
      gState.getNodeVal(curr) == "const":
        return true
    curr = curr.tsNodePrevNamedSibling()

  # Check immediate next sibling
  curr = node.tsNodePrevNamedSibling()
  if curr.getName() == "type_qualifier" and
    gState.getNodeVal(curr) == "const":
      return true

proc getXCount*(node: TSNode, ntype: string, reverse = false): int =
  if not node.isNil:
    # Get number of ntype nodes nested in tree
    var
      cnode = node
    while ntype in cnode.getName():
      result += 1
      if reverse:
        cnode = cnode.tsNodeParent()
      else:
        if cnode.len != 0:
          if cnode[0].getName() == "type_qualifier":
            # Skip const, volatile
            if cnode.len > 1:
              cnode = cnode[1]
            else:
              break
          else:
            cnode = cnode[0]
        else:
          break

proc getPtrCount*(node: TSNode, reverse = false): int =
  node.getXCount("pointer_declarator")

proc getArrayCount*(node: TSNode, reverse = false): int =
  node.getXCount("array_declarator")

proc getDeclarator*(node: TSNode): TSNode =
  if not node.isNil:
    # Return if child is a function or array declarator
    if node.getName() in ["function_declarator", "array_declarator"]:
      return node
    elif node.len != 0:
      return node[0].getDeclarator()

proc getVarargs*(node: TSNode): bool =
  # Detect ... and add {.varargs.}
  #
  # `node` is the param list
  #
  # ... is an unnamed node, second last node and ) is last node
  let
    nlen = node.tsNodeChildCount()
  if nlen > 1.uint32:
    let
      nval = node.tsNodeChild(nlen - 2.uint32).getName()
    if nval == "...":
      result = true

proc firstChildInTree*(node: TSNode, ntype: string): TSNode =
  # Search for node type in tree - first children
  var
    cnode = node
  while not cnode.isNil:
    if cnode.getName() == ntype:
      return cnode
    cnode = cnode[0]

proc anyChildInTree*(node: TSNode, ntype: string): TSNode =
  # Search for node type anywhere in tree - depth first
  var
    cnode = node
  while not cnode.isNil:
    if cnode.getName() == ntype:
      return cnode
    for i in 0 ..< cnode.len:
      let
        ccnode = cnode[i].anyChildInTree(ntype)
      if not ccnode.isNil:
        return ccnode
    if cnode != node:
      cnode = cnode.tsNodeNextNamedSibling()
    else:
      break

proc mostNestedChildInTree*(node: TSNode): TSNode =
  # Search for the most nested child of node's type in tree
  var
    cnode = node
    ntype = cnode.getName()
  while not cnode.isNil and cnode.len != 0 and cnode[0].getName() == ntype:
    cnode = cnode[0]
  result = cnode

proc inChildren*(node: TSNode, ntype: string): bool =
  # Search for node type in immediate children
  result = false
  for i in 0 ..< node.len:
    if (node[i]).getName() == ntype:
      result = true
      break

proc getLineCol*(code: var string, node: TSNode): tuple[line, col: int] =
  # Get line number and column info for node
  let
    point = node.tsNodeStartPoint()
  result.line = point.row.int + 1
  result.col = point.column.int + 1

proc getLineCol*(gState: State, node: TSNode): tuple[line, col: int] =
  getLineCol(gState.code, node)

proc getEndLineCol*(code: var string, node: TSNode): tuple[line, col: int] =
  # Get line number and column info for node
  let
    point = node.tsNodeEndPoint()
  result.line = point.row.int + 1
  result.col = point.column.int + 1

proc getEndLineCol*(gState: State, node: TSNode): tuple[line, col: int] =
  getEndLineCol(gState.code, node)

proc getTSNodeNamedChildCountSansComments*(node: TSNode): int =
  for i in 0 ..< node.len:
    if node.getName() != "comment":
      result += 1

proc getPxName*(node: TSNode, offset: int): string =
  # Get the xth (grand)parent of the node
  var
    np = node
    count = 0

  while not np.isNil and count < offset:
    np = np.tsNodeParent()
    count += 1

  if count == offset and not np.isNil:
    return np.getName()

proc printLisp*(code: var string, root: TSNode): string =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.isNil and depth > -1:
      result &= spaces(depth)
      let
        (line, col) = code.getLineCol(node)
      result &= &"({$node.tsNodeType()} {line} {col} {node.tsNodeEndByte() - node.tsNodeStartByte()}"
      let
        val = code.getNodeVal(node)
      if "\n" notin val and " " notin val:
        result &= &" \"{val}\""
    else:
      break

    if node.len() != 0:
      result &= "\n"
      nextnode = node[0]
      depth += 1
    else:
      result &= ")\n"
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.isNil:
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if depth == -1:
          break
        result &= spaces(depth) & ")\n"
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().isNil:
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc printLisp*(gState: State, root: TSNode): string =
  printLisp(gState.code, root)

proc printDebug*(gState: State, node: TSNode) =
  if gState.debug:
    gecho ("Input => " & gState.getNodeVal(node)).getCommented()
    gecho gState.printLisp(node).getCommented()

proc getCommentsStr*(gState: State, commentNodes: seq[TSNode]): string =
  ## Generate a comment from a set of comment nodes. Comment is guaranteed
  ## to be able to be rendered using nim doc
  if commentNodes.len > 0:
    for commentNode in commentNodes:
      result &= "\n  " & gState.getNodeVal(commentNode).strip()

    result = "```\n  " & result.multiReplace(
      {
        "/**": "", "**/": "", "/*": "",
        "*/": "", "/*": "", "//": "",
        "\n": "\n  ", "`": ""
        }
    # need to replace this last otherwise it supercedes other replacements
    ).replace(" *", "").strip() & "\n```"

proc getCommentNodes*(gState: State, node: TSNode, maxSearch=1): seq[TSNode] =
  ## Get a set of comment nodes in order of priority. Will search up to ``maxSearch``
  ## nodes before and after the current node
  ##
  ## Priority is (closest line number) > comment before > comment after.
  ## This priority might need to be changed based on the project, but
  ## for now it is good enough

  # Skip this if we don't want comments
  if gState.noComments:
    return

  let (line, _) = gState.getLineCol(node)

  # Keep track of both directions from a node
  var
    prevSibling = node.tsNodePrevNamedSibling()
    nextSibling = node.tsNodeNextNamedSibling()
    nilNode: TSNode

  var
    i = 0
    prevSiblingDistance, nextSiblingDistance: int = int.high
    lowestDistance: int
    commentsFound = false

  while not commentsFound and i < maxSearch:
    # Distance from the current node will tell us approximately if the
    # comment belongs to the node. The closer it is in terms of line
    # numbers, the more we can be sure it's the comment we want
    if not prevSibling.isNil:
      if prevSibling.getName() == "comment":
        prevSiblingDistance = abs(gState.getEndLineCol(prevSibling)[0] - line)
      else:
        prevSiblingDistance = int.high
    if not nextSibling.isNil:
      if nextSibling.getName() == "comment":
        nextSiblingDistance = abs(gState.getLineCol(nextSibling)[0] - line)
      else:
        nextSiblingDistance = int.high

    lowestDistance = min(prevSiblingDistance, nextSiblingDistance)

    if prevSiblingDistance > maxSearch:
      # If the line is out of range, skip searching
      prevSibling = nilNode # Can't do `= nil`

    if nextSiblingDistance > maxSearch:
      # If the line is out of range, skip searching
      nextSibling = nilNode

    # Search above the current line for comments. When one is found
    # keep going to retrieve successive comments for cases with multiple
    # `//` style comments
    while (
      not prevSibling.isNil and
      prevSibling.getName() == "comment" and
      prevSiblingDistance == lowestDistance
    ):
      # Put the previous nodes in reverse order so the comments
      # make logical sense
      result.insert(prevSibling, 0)
      prevSibling = prevSibling.tsNodePrevNamedSibling()
      commentsFound = true

    # If we've already found comments above the current line, quit
    if commentsFound:
      break

    # Search below or at the current line for comments. When one is found
    # keep going to retrieve successive comments for cases with multiple
    # `//` style comments
    while (
      not nextSibling.isNil and
      nextSibling.getName() == "comment" and
      nextSiblingDistance == lowestDistance
    ):
      result.add(nextSibling)
      nextSibling = nextSibling.tsNodeNextNamedSibling()
      commentsFound = true

    if commentsFound:
      break

    # Go to next sibling pair
    if not prevSibling.isNil:
      prevSibling = prevSibling.tsNodePrevNamedSibling()
    if not nextSibling.isNil:
      nextSibling = nextSibling.tsNodeNextNamedSibling()

    i += 1

proc getTSNodeNamedChildNames*(node: TSNode): seq[string] =
  if node.tsNodeNamedChildCount() != 0:
    for i in 0 .. node.tsNodeNamedChildCount()-1:
      let
        name = $node.tsNodeNamedChild(i).tsNodeType()

      if name != "comment":
        result.add(name)
