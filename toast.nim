import os, strutils

import regex

import treesitter/[runtime, c, cpp]

const HELP = """
> toast header.h
"""

var
  gPretty = true

proc printLisp(root: TSNode, data: var string) =
  var
    node = root
    nextnode: TSNode
    depth = 0
    
  while true:
    if not node.tsNodeIsNull():
      if gPretty:
        stdout.write spaces(depth)
      stdout.write "(" & $node.tsNodeType() & " " & $node.tsNodeStartByte() & " " & $node.tsNodeEndByte()

    if node.tsNodeNamedChildCount() != 0:
      if gPretty:
        echo ""
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      if gPretty:
        echo ")"
      else:
        stdout.write ")"
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.tsNodeIsNull():
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if gPretty:
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

proc process(path: string, mode="") =
  if not existsFile(path):
    echo "Invalid path " & path
    return
  
  var
    parser = tsParserNew()
    ext = path.splitFile().ext
    pmode = ""
    data = readFile(path)

  defer:
    parser.tsParserDelete()
    
  if mode.len() != 0:
    pmode = mode
  elif ext in [".h", ".c"]:
    pmode = "c"
  elif ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
    pmode = "cpp"
  
  if "cplusplus" in data or "extern \"C\"" in data:
    pmode = "cpp"

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
    tree = parser.tsParserParseString(nil, data.cstring, data.len().uint32)
    root = tree.tsTreeRootNode()

  defer:
    tree.tsTreeDelete()
    
  printLisp(root, data)

proc parseCli() =
  let params = commandLineParams()
  for param in params:
    if param in ["-h", "--help", "-?", "/?", "/h"]:
      echo HELP
      quit()
    elif param == "-u":
      gPretty = false
    else:
      process(param)

parseCli()