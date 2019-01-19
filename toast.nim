import os, strformat, strutils

import nimterop/treesitter/[runtime, c, cpp]

import nimterop/[ast, globals, getters, grammar]

proc printLisp(root: TSNode) =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.tsNodeIsNull():
      if gStateRT.pretty:
        stdout.write spaces(depth)
      let
        (line, col) = node.getLineCol()
      stdout.write &"({$node.tsNodeType()} {line} {col} {node.tsNodeEndByte() - node.tsNodeStartByte()}"
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

  gStateRT.sourceFile = path

  if gStateRT.mode.len == 0:
    if ext in [".h", ".c"]:
      gStateRT.mode = "c"
    elif ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
      gStateRT.mode = "cpp"

  if gStateRT.preprocess:
    gStateRT.code = getPreprocessor(path)
  else:
    gStateRT.code = readFile(path)

  doAssert gStateRT.code.len != 0, "Empty file or preprocessor error"

  if gStateRT.mode == "c":
    doAssert parser.tsParserSetLanguage(treeSitterC()), "Failed to load C parser"
  elif gStateRT.mode == "cpp":
    doAssert parser.tsParserSetLanguage(treeSitterCpp()), "Failed to load C++ parser"
  else:
    doAssert false, "Invalid parser " & gStateRT.mode

  var
    tree = parser.tsParserParseString(nil, gStateRT.code.cstring, gStateRT.code.len.uint32)
    root = tree.tsTreeRootNode()

  defer:
    tree.tsTreeDelete()

  if gStateRT.past:
    printLisp(root)
  elif gStateRT.pnim:
    printNim(path, root)
  elif gStateRT.preprocess:
    echo gStateRT.code

proc main(
    mode = modeDefault,
    past = false,
    pnim = false,
    pretty = true,
    preprocess = false,
    pgrammar = false,
    recurse = false,
    debug = false,
    defines: seq[string] = @[],
    includeDirs: seq[string] = @[],
    source: seq[string],
  ) =

  gStateRT = State(
    mode: mode,
    past: past,
    pnim: pnim,
    pretty: pretty,
    preprocess: preprocess,
    recurse: recurse,
    debug: debug,
    defines: defines,
    includeDirs: includeDirs,
  )

  if pgrammar:
    parseGrammar()
    printGrammar()
  elif source.len != 0:
    process(source[0])

when isMainModule:
  import cligen
  dispatch(main, help = {
    "past": "print AST output",
    "mode": "language; see CompileMode", # TODO: auto-generate valid choices
    "pnim": "print Nim output",
    "defines": "definitions to pass to preprocessor",
    "includeDirs": "include directory to pass to preprocessor",
    "preprocess": "run preprocessor on header",
    "pgrammar": "print grammar",
    "recurse": "process #include files",
    "debug": "enable debug output",
    "source" : "C/C++ source/header",
  }, short = {
    "past": 'a',
    "pnim": 'n',
    "defines": 'D',
    "includeDirs": 'I',
    "preprocess": 'p',
    "recurse": 'r',
    "debug": 'd',
    "pgrammar": 'g'
  })
