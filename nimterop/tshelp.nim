template withCodeAst*(inputCode: string, inputMode: string, body: untyped): untyped =
  ## A simple template to inject the TSNode into a body of code

  # This section is needed to be able to reference
  # mode in strformat calls
  let
    code = inputCode
    mode {.inject.} = inputMode

  var parser = tsParserNew()
  defer:
    parser.tsParserDelete()

  doAssert code.nBl, "Empty code or preprocessor error"

  if mode == "c":
    doAssert parser.tsParserSetLanguage(treeSitterC()), "Failed to load C parser"
  elif mode == "cpp":
    doAssert parser.tsParserSetLanguage(treeSitterCpp()), "Failed to load C++ parser"
  else:
    doAssert false, &"Invalid parser {mode}"

  var
    tree = parser.tsParserParseString(nil, code.cstring, code.len.uint32)
    root {.inject.} = tree.tsTreeRootNode()

  body

  defer:
    tree.tsTreeDelete()