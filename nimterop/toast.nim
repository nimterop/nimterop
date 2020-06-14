import os, osproc, sets, strformat, strutils, tables, times

import "."/treesitter/[api, c, cpp]

import "."/[ast, ast2, build, globals, getters, grammar, tshelp]

proc process(gState: State, path: string, astTable: AstTable) =
  doAssert existsFile(path), &"Invalid path {path}"

  if gState.mode.Bl:
    gState.mode = getCompilerMode(path)

  if gState.preprocess:
    gState.getPreprocessor(path)
  else:
    gState.code = readFile(path)

  withCodeAst(gState.code, gState.mode):
    if gState.past:
      gecho gState.printLisp(root)
    elif gState.pnim:
      if Feature.ast2 in gState.feature:
        ast2.parseNim(gState, path, root)
      elif Feature.ast1 in gState.feature:
        ast.parseNim(gState, path, root, astTable)
    elif gState.preprocess:
      gecho gState.code

# CLI processing with default values
proc main(
    check = false,
    convention = "cdecl",
    debug = false,
    defines: seq[string] = @[],
    dynlib: string = "",
    feature: seq[Feature] = @[],
    includeDirs: seq[string] = @[],
    mode = "",
    nim: string = "nim",
    noComments = false,
    noHeader = false,
    output = "",
    past = false,
    pgrammar = false,
    pluginSourcePath: string = "",
    pnim = false,
    prefix: seq[string] = @[],
    preprocess = false,
    recurse = false,
    replace: seq[string] = @[],
    stub = false,
    suffix: seq[string] = @[],
    symOverride: seq[string] = @[],
    typeMap: seq[string] = @[],
    source: seq[string]
  ) =

  # Setup global state with arguments
  var gState = State(
    convention: convention,
    debug: debug,
    defines: defines,
    dynlib: dynlib,
    feature: feature,
    includeDirs: includeDirs,
    mode: mode,
    nim: nim.sanitizePath,
    noComments: noComments,
    noHeader: noHeader,
    past: past,
    pluginSourcePath: pluginSourcePath,
    pnim: pnim,
    prefix: prefix,
    preprocess: preprocess,
    recurse: recurse,
    replace: newOrderedTable[string, string](),
    suffix: suffix,
    symOverride: symOverride
  )

  # Set gDebug in build.nim
  build.gDebug = gState.debug
  build.gNimExe = gState.nim

  # Default `ast` mode
  if gState.feature.Bl:
    gState.feature.add Feature.ast1

  # Split some arguments with ,
  gState.symOverride = gState.symOverride.getSplitComma()
  gState.prefix = gState.prefix.getSplitComma()
  gState.suffix = gState.suffix.getSplitComma()

  # Replace => Table
  for i in replace.getSplitComma():
    let
      nv = i.split("=", maxsplit = 1)
      name = nv[0]
      value = if nv.len == 2: nv[1] else: ""
    gState.replace[name] = value

  # typeMap => getters.gTypeMap
  for i in typeMap.getSplitComma():
    let
      nv = i.split("=", maxsplit = 1)
    doAssert nv.len == 2, "`--typeMap` requires X=Y format"
    gTypeMap[nv[0]] = nv[1]
    gTypeMapValues.incl nv[1]

  if pluginSourcePath.nBl:
    gState.loadPlugin(pluginSourcePath)

  var
    outputFile = output
    check = check or stub

  # Fix output file extention for Nim mode
  if outputFile.len != 0 and pnim:
    if outputFile.splitFile().ext != ".nim":
      outputFile = outputFile & ".nim"

  # Check needs a file
  if check and outputFile.len == 0:
    outputFile = getTempDir() / "toast_" & ($getTime().toUnix()).addFileExt("nim")

  # Recurse implies preprocess
  if gState.recurse:
    gState.preprocess = true

  # Redirect output to file
  if outputFile.len != 0:
    doAssert gState.outputHandle.open(outputFile, fmWrite),
      &"Failed to write to {outputFile}"

    if gState.debug:
      echo &"# Writing output to {outputFile}\n"

  # Process grammar into AST
  let
    astTable =
      if Feature.ast1 in gState.feature:
        parseGrammar()
      else:
        nil

  if pgrammar:
    if Feature.ast1 in gState.feature:
      # Print AST of grammar
      gState.printGrammar(astTable)
  elif source.nBl:
    # Print source after preprocess or Nim output
    if gState.pnim:
      gState.initNim()
    for src in source:
      gState.process(src.expandSymlinkAbs(), astTable)
    if gState.pnim:
      if Feature.ast2 in gState.feature:
        ast2.printNim(gState)
      elif Feature.ast1 in gState.feature:
        ast.printNim(gState)
        gecho """{.hint: "The legacy wrapper generation algorithm is deprecated and will be removed in the next release of Nimterop.".}"""
        gecho """{.hint: "Refer to CHANGES.md for details on migrating to the new backend.".}"""

  # Close outputFile
  if outputFile.len != 0:
    gState.outputHandle.close()

  # Check Nim output
  if gState.pnim and check:
    # Run nim check on generated wrapper
    var
      (check, err) = execCmdEx(&"{gState.nim} check {outputFile}")
    if err != 0:
      # Failed check so try stubbing
      if stub:
        # Find undeclared identifiers in error
        var
          data = ""
          stubData = ""
        for line in check.splitLines:
          if "undeclared identifier" in line:
            try:
              # Add stub of object type
              stubData &= "  " & line.split("'")[1] & " = object\n"
            except:
              discard

        # Include in wrapper file
        data = outputFile.readFile()
        let
          idx = data.find("\ntype\n")
        if idx != -1:
          # In first existing type block
          data = data[0 ..< idx+6] & stubData & data[idx+6 .. ^1]
        else:
          # At the top if none already
          data = "type\n" & stubData & data
        outputFile.writeFile(data)

        # Rerun nim check on stubbed wrapper
        (check, err) = execCmdEx(&"{gState.nim} check {outputFile}")
        doAssert err == 0, data & "\n# Nim check with stub failed:\n\n" & check
      else:
        doAssert err == 0, outputFile.readFile() & "\n# Nim check failed:\n\n" & check

  # Print wrapper if temporarily redirected to file
  if check and output.len == 0:
    stdout.write outputFile.readFile()

proc mergeParams(cmdNames: seq[string], cmdLine = commandLineParams()): seq[string] =
  # Load command-line params from `source` if it is a .cfg file
  if cmdNames.len != 0:
    # https://github.com/c-blake/cligen/issues/149
    for param in cmdLine:
      if param.fileExists() and param.splitFile().ext == ".cfg":
        echo &"# Loading flags from '{param}'"
        for line in param.readFile().splitLines():
          let
            line = line.strip()
          if line.len > 1 and line[0] != '#':
            result.add line.parseCmdLine()
      else:
        result.add param

    if result.len != 0 and "-h" notin result and "--help" notin result:
      echo &"""# Generated @ {$now()}
# Command line:
#   {getAppFilename()} {result.join(" ")}
"""
  else:
    result = cmdLine

when isMainModule:
  # Setup cligen command line help and short flags
  import cligen
  dispatch(main, help = {
    "check": "check generated wrapper with compiler",
    "convention": "calling convention for wrapped procs",
    "debug": "enable debug output",
    "defines": "definitions to pass to preprocessor",
    "dynlib": "import symbols from library in specified Nim string",
    "feature": "flags to enable experimental features",
    "includeDirs": "include directory to pass to preprocessor",
    "mode": "language parser: c or cpp",
    "nim": "use a particular Nim executable",
    "noComments": "exclude top-level comments from output",
    "noHeader": "skip {.header.} pragma in wrapper",
    "output": "file to output content - default: stdout",
    "past": "print AST output",
    "pgrammar": "print grammar",
    "pluginSourcePath": "nim file to build and load as a plugin",
    "pnim": "print Nim output",
    "prefix": "strip prefix from identifiers",
    "preprocess": "run preprocessor on header",
    "recurse": "process #include files - implies --preprocess",
    "replace": "replace X with Y in identifiers, X1=Y1,X2=Y2, @X for regex",
    "source" : "C/C++ source/header(s) and command line file(s)",
    "stub": "stub out undefined type references as objects",
    "suffix": "strip suffix from identifiers",
    "symOverride": "skip generating specified symbols",
    "typeMap": "map instances of type X to Y - e.g. ABC=cint"
  }, short = {
    "check": 'k',
    "convention": 'C',
    "debug": 'd',
    "defines": 'D',
    "dynlib": 'l',
    "feature": 'f',
    "includeDirs": 'I',
    "noComments": 'c',
    "noHeader": 'H',
    "output": 'o',
    "past": 'a',
    "pgrammar": 'g',
    "pnim": 'n',
    "prefix": 'E',
    "preprocess": 'p',
    "recurse": 'r',
    "replace": 'G',
    "stub": 's',
    "suffix": 'F',
    "symOverride": 'O',
    "typeMap": 'T'
  })
