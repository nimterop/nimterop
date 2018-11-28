import os, strutils

import treesitter/[runtime, c, cpp]

import nimterop/[ast, globals, getters]

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

  if gStateRT.mode.len == 0:
    gStateRT.mode = modeDefault
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

proc main(
    mode = modeDefault,
    past = false,
    pnim = false,
    pretty = true,
    preprocess = false,
    defines: seq[string] = @[],
    includeDirs: seq[string] = @[],
    # defines.add(param[2..^1].strip(chars={'"'}))
    source: string,
  ) =
  # TODO: should we add back `-m` param? meaning was:  print minimized AST output - non-pretty (implies -a)

  gStateRT = State(
    mode: mode,
    past: past,
    pnim: pnim,
    pretty: pretty,
    preprocess: preprocess,
    # Note: was: strip(chars={'"'} but that seemed buggy (the shell should remove these already)
    defines: defines,
    includeDirs: includeDirs,
  )
  process(source)

when isMainModule:
  import cligen
  dispatch(main, help = {
    "past": "print AST output",
    "mode": "language; see CompileMode", # TODO: auto-generate valid choices
    "pnim": "run preprocessor on header",
    "defines": "definitions to pass to preprocessor",
    "includeDirs": "include directory to pass to preprocessor",
    "preprocess": "print Nim output",
    "source" : "C/C++ source/header",
  })
