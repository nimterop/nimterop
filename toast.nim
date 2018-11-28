import os, strutils

import treesitter/[runtime, c, cpp]

import nimterop/[ast, globals, getters]

const HELP = """
> toast header.h
-a     print AST output
-m     print minimized AST output - non-pretty (implies -a)
-n     print Nim output

-c     C mode - CPP is default
-p     run preprocessor on header
-D     definitions to pass to preprocessor
-I     include directory to pass to preprocessor"""

proc printLisp(root: TSNode) =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.tsNodeIsNull():
      if gStateRT.pretty:
        stdout.write spaces(depth)
      stdout.write "(" & $node.tsNodeType() & " " & $node.tsNodeStartByte() & " " & $node.tsNodeEndByte()
    else:
      return

    if node.tsNodeNamedChildCount() != 0:
      if gStateRT.pretty:
        echo ""
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      if gStateRT.pretty:
        echo ")"
      else:
        stdout.write ")"
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.tsNodeIsNull():
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if depth == -1:
          break
        if gStateRT.pretty:
          echo spaces(depth) & ")"
        else:
          stdout.write ")"
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().tsNodeIsNull():
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc process(path: string) =
  if not existsFile(path):
    echo "Invalid path " & path
    return

  var
    parser = tsParserNew()
    ext = path.splitFile().ext

  defer:
    parser.tsParserDelete()

  if gStateRT.mode.len != 0:
    gStateRT.mode = "cpp"
  elif ext in [".h", ".c"]:
    gStateRT.mode = "c"
  elif ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
    gStateRT.mode = "cpp"

  if gStateRT.preprocess:
    gStateRT.code = getPreprocessor(path)
  else:
    gStateRT.code = readFile(path)

  if gStateRT.mode == "c":
    if not parser.tsParserSetLanguage(treeSitterC()):
      echo "Failed to load C parser"
      quit()
  elif gStateRT.mode == "cpp":
    if not parser.tsParserSetLanguage(treeSitterCpp()):
      echo "Failed to load C++ parser"
      quit()
  else:
    echo "Invalid parser " & gStateRT.mode
    quit()

  var
    tree = parser.tsParserParseString(nil, gStateRT.code.cstring, gStateRT.code.len.uint32)
    root = tree.tsTreeRootNode()

  defer:
    tree.tsTreeDelete()

  if gStateRT.past:
    printLisp(root)
  elif gStateRT.pnim:
    printNim(path, root)

proc parseCli() =
  var params = commandLineParams()

  gStateRT.mode = "cpp"
  gStateRT.past = false
  gStateRT.pnim = false
  gStateRT.pretty = true
  gStateRT.preprocess = false

  for param in params:
    let flag = if param.len() <= 2: param else: param[0..<2]

    if flag in ["-h", "-?"]:
      echo HELP
      quit()
    elif flag == "-a":
      gStateRT.past = true
    elif flag == "-c":
      gStateRT.mode = "c"
    elif flag == "-m":
      gStateRT.past = true
      gStateRT.pretty = false
    elif flag == "-n":
      gStateRT.pnim = true
    elif flag == "-p":
      gStateRT.preprocess = true
    elif flag == "-D":
      gStateRT.defines.add(param[2..^1].strip(chars={'"'}))
    elif flag == "-I":
      gStateRT.includeDirs.add(param[2..^1].strip(chars={'"'}))
    else:
      process(param)

parseCli()
