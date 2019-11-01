import os, strformat, strutils

import "."/treesitter/[api, c, cpp]

import "."/[ast, globals, getters, grammar]

proc printLisp(gState: State, root: TSNode) =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.tsNodeIsNull() and depth > -1:
      if gState.pretty:
        stdout.write spaces(depth)
      let
        (line, col) = gState.getLineCol(node)
      stdout.write &"({$node.tsNodeType()} {line} {col} {node.tsNodeEndByte() - node.tsNodeStartByte()}"
    else:
      break

    if node.tsNodeNamedChildCount() != 0:
      if gState.pretty:
        echo ""
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      if gState.pretty:
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
        if gState.pretty:
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

proc process(gState: State, path: string, astTable: AstTable) =
  doAssert existsFile(path), "Invalid path " & path

  var
    parser = tsParserNew()
    ext = path.splitFile().ext

  defer:
    parser.tsParserDelete()

  if gState.mode.Bl:
    if ext in [".h", ".c"]:
      gState.mode = "c"
    elif ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
      gState.mode = "cpp"

  if gState.preprocess:
    gState.code = gState.getPreprocessor(path)
  else:
    gState.code = readFile(path)

  doAssert gState.code.nBl, "Empty file or preprocessor error"

  if gState.mode == "c":
    doAssert parser.tsParserSetLanguage(treeSitterC()), "Failed to load C parser"
  elif gState.mode == "cpp":
    doAssert parser.tsParserSetLanguage(treeSitterCpp()), "Failed to load C++ parser"
  else:
    doAssert false, "Invalid parser " & gState.mode

  var
    tree = parser.tsParserParseString(nil, gState.code.cstring, gState.code.len.uint32)
    root = tree.tsTreeRootNode()

  defer:
    tree.tsTreeDelete()

  if gState.past:
    gState.printLisp(root)
  elif gState.pnim:
    gState.printNim(path, root, astTable)
  elif gState.preprocess:
    echo gState.code

proc main(
    preprocess = false,
    past = false,
    pnim = false,
    recurse = false,
    nocomments = false,
    defines: seq[string] = @[],
    includeDirs: seq[string] = @[],
    dynlib: string = "",
    symOverride: seq[string] = @[],
    nim: string = "nim",
    pluginSourcePath: string = "",
    debug = false,
    mode = modeDefault,
    pgrammar = false,
    source: seq[string]
  ) =

  var gState = State(
    preprocess: preprocess,
    past: past,
    pnim: pnim,
    recurse: recurse,
    nocomments: nocomments,
    defines: defines,
    includeDirs: includeDirs,
    dynlib: dynlib,
    symOverride: symOverride,
    nim: nim,
    pluginSourcePath: pluginSourcePath,
    debug: debug,
    mode: mode,
    pretty: true
  )

  gState.symOverride = gState.symOverride.getSplitComma()

  if pluginSourcePath.nBl:
    gState.loadPlugin(pluginSourcePath)

  let
    astTable = parseGrammar()
  if pgrammar:
    astTable.printGrammar()
  elif source.nBl:
    if gState.pnim:
      printNimHeader()
    for src in source:
      gState.process(src.expandSymlinkAbs(), astTable)

when isMainModule:
  import cligen
  dispatch(main, help = {
    "preprocess": "run preprocessor on header",
    "past": "print AST output",
    "pnim": "print Nim output",
    "recurse": "process #include files",
    "nocomments": "exclude top-level comments from output",
    "defines": "definitions to pass to preprocessor",
    "includeDirs": "include directory to pass to preprocessor",
    "dynlib": "Import symbols from library in specified Nim string",
    "symOverride": "skip generating specified symbols",
    "nim": "use a particular Nim executable (default: $PATH/nim)",
    "pluginSourcePath": "Nim file to build and load as a plugin",
    "debug": "enable debug output",
    "mode": "language parser: c or cpp",
    "pgrammar": "print grammar",
    "source" : "C/C++ source/header"
  }, short = {
    "preprocess": 'p',
    "past": 'a',
    "pnim": 'n',
    "recurse": 'r',
    "nocomments": 'c',
    "defines": 'D',
    "includeDirs": 'I',
    "dynlib": 'l',
    "symOverride": 'O',
    "debug": 'd',
    "pgrammar": 'g'
  })
