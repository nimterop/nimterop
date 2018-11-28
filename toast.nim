import os, strutils

import treesitter/[runtime, c, cpp]

import nimterop/[globals, getters]

const HELP = """
> toast header.h
-a     print AST output
-c     C mode - CPP is default
-m     print minimized AST output - non-pretty (implies -a)
-p     run preprocessor on header
-D     definitions to pass to preprocessor
-I     include directory to pass to preprocessor"""

proc printLisp(root: TSNode, data: var string, pretty = true) =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.tsNodeIsNull():
      if pretty:
        stdout.write spaces(depth)
      stdout.write "(" & $node.tsNodeType() & " " & $node.tsNodeStartByte() & " " & $node.tsNodeEndByte()
    else:
      return

    if node.tsNodeNamedChildCount() != 0:
      if pretty:
        echo ""
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      if pretty:
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
        if pretty:
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

proc process(path: string, mode="cpp", past, pretty, preprocess: bool) =
  if not existsFile(path):
    echo "Invalid path " & path
    return

  var
    parser = tsParserNew()
    ext = path.splitFile().ext
    pmode = ""
    data = ""

  defer:
    parser.tsParserDelete()

  if mode.len != 0:
    pmode = mode
  elif ext in [".h", ".c"]:
    pmode = "c"
  elif ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
    pmode = "cpp"

  if preprocess:
    data = getPreprocessor(path)
  else:
    data = readFile(path)

  if pmode == "c":
    if not parser.tsParserSetLanguage(treeSitterC()):
      echo "Failed to load C parser"
      quit()
  elif pmode == "cpp":
    if not parser.tsParserSetLanguage(treeSitterCpp()):
      echo "Failed to load C++ parser"
      quit()
  else:
    echo "Invalid parser " & mode
    quit()

  var
    tree = parser.tsParserParseString(nil, data.cstring, data.len.uint32)
    root = tree.tsTreeRootNode()

  defer:
    tree.tsTreeDelete()

  if past:
    printLisp(root, data, pretty)

proc parseCli() =
  var
    mode = "cpp"
    params = commandLineParams()

    past = false
    pretty = true
    preprocess = false

  for param in params:
    let flag = if param.len() <= 2: param else: param[0..<2]

    if flag in ["-h", "-?"]:
      echo HELP
      quit()
    elif flag == "-a":
      past = true
    elif flag == "-c":
      mode = "c"
    elif flag == "-m":
      past = true
      pretty = false
    elif flag == "-p":
      preprocess = true
    elif flag == "-D":
      gDefinesRT.add(param[2..^1])
    elif flag == "-I":
      gIncludeDirsRT.add(param[2..^1])
    else:
      process(param, mode, past, pretty, preprocess)

parseCli()
