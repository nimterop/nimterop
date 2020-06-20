import dynlib, macros, os, sequtils, sets, strformat, strutils, tables, times

import regex

import ".."/[build, globals, plugin]

const gReserved = """
addr and as asm
bind block break
case cast concept const continue converter
defer discard distinct div do
elif else end enum except export
finally for from func
if import in include interface is isnot iterator
let
macro method mixin mod
nil not notin
of or out
proc ptr
raise ref return
shl shr static
template try tuple type
using
var
when while
xor
yield""".split(Whitespace).toHashSet()

# Types related

var
  gTypeMap* = {
    # char
    "char": "cchar",
    "signed char": "cschar",
    "unsigned char": "cuchar",

    # short
    "short": "cshort",
    "short int": "cshort",
    "signed short": "cshort",
    "signed short int": "cshort",
    "unsigned short": "cushort",
    "unsigned short int": "cushort",
    "uShort": "cushort",
    "u_short": "cushort",

    # int
    "int": "cint",
    "signed": "cint",
    "signed int": "cint",
    "ssize_t": "int",
    "unsigned": "cuint",
    "unsigned int": "cuint",
    "uInt": "cuint",
    "u_int": "cuint",
    "size_t": "uint",

    "int8_t": "int8",
    "int16_t": "int16",
    "int32_t": "int32",
    "int64_t": "int64",

    "intptr_t": "ptr int",

    "Int8": "int8",
    "Int16": "int16",
    "Int32": "int32",
    "Int64": "int64",

    "uint8_t": "uint8",
    "uint16_t": "uint16",
    "uint32_t": "uint32",
    "uint64_t": "uint64",

    "uintptr_t": "ptr uint",

    "Uint8": "uint8",
    "Uint16": "uint16",
    "Uint32": "uint32",
    "Uint64": "uint64",

    # long
    "long": "clong",
    "long int": "clong",
    "signed long": "clong",
    "signed long int": "clong",
    "off_t": "clong",
    "unsigned long": "culong",
    "unsigned long int": "culong",
    "uLong": "culong",
    "u_long": "culong",

    # long long
    "long long": "clonglong",
    "long long int": "clonglong",
    "signed long long": "clonglong",
    "signed long long int": "clonglong",
    "off64_t": "clonglong",
    "unsigned long long": "culonglong",
    "unsigned long long int": "culonglong",

    # floating point
    "float": "cfloat",
    "double": "cdouble",
    "long double": "clongdouble",

    # Misc Nim types
    "Bool": "bool"
  }.toTable()

  # Nim type names that shouldn't need to be wrapped again
  gTypeMapValues* = toSeq(gTypeMap.values).toHashSet()

proc getType*(str: string): string =
  if str == "void":
    return "object"

  result = str.strip(chars={'_'}).splitWhitespace().join(" ")

  if gTypeMap.hasKey(result):
    result = gTypeMap[result]

# Identifier related

proc checkIdentifier(name, kind, parent, origName: string) =
  let
    parentStr = if parent.nBl: parent & ":" else: ""

  if name.nBl:
    let
      origStr = if name != origName: &", originally '{origName}' before 'cPlugin:onSymbol()', still" else: ""
      errmsg = &"Identifier '{parentStr}{name}' ({kind}){origStr} contains $1 " &
        "which Nim does not allow. Use toast flag '$2' or 'cPlugin()' to modify."

    doAssert name[0] != '_' and name[^1] != '_', errmsg % ["leading/trailing underscores '_'", "--prefix or --suffix"]

    doAssert (not name.contains("__")): errmsg % ["consecutive underscores '_'", "--replace"]

  # Cannot blank out symbols which are fields or params
  #
  # `IgnoreSkipSymbol` is used to `getIdentifier()` even if symbol is in `symOverride` list
  # so that any prefix/suffix/replace or `onSymbol()` processing can occur. This is only used
  # for `cOverride()` since it also depends on `symOverride`.
  if parent.nBl and parent != "IgnoreSkipSymbol":
    doAssert name.nBl, &"Blank identifier, originally '{parentStr}{origName}' ({kind}), cannot be empty"

proc getIdentifier*(gState: State, name: string, kind: NimSymKind, parent=""): string =
  doAssert name.nBl, "Blank identifier error"

  if name notin gState.symOverride or parent.nBl:
    if gState.onSymbol != nil:
      # Use onSymbol from plugin provided by user
      var
        sym = Symbol(name: name, parent: parent, kind: kind)
      gState.onSymbol(sym)

      result = sym.name
    else:
      result = name

      # Strip out --prefix from CLI if specified
      for str in gState.prefix:
        if result.startsWith(str):
          result = result[str.len .. ^1]

      # Strip out --suffix from CLI if specified
      for str in gState.suffix:
        if result.endsWith(str):
          result = result[0 .. ^(str.len+1)]

      # --replace from CLI if specified
      for name, value in gState.replace.pairs:
          if name.len > 1 and name[0] == '@':
            result = result.replace(re(name[1 .. ^1]), value)
          else:
            result = result.replace(name, value)

    checkIdentifier(result, $kind, parent, name)

    if result in gReserved or (result == "object" and kind != nskType):
      # Enclose in backticks since Nim reserved word
      result = &"`{result}`"
  else:
    # Skip identifier since in symOverride
    result = ""

proc getUniqueIdentifier*(gState: State, prefix = ""): string =
  var
    name = prefix & "_" & gState.sourceFile.extractFilename().multiReplace([(".", ""), ("-", "")])
    nimName = name[0] & name[1 .. ^1].replace("_", "").toLowerAscii
    count = 1

  while (nimName & $count) in gState.identifiers:
    count += 1

  return name & $count

proc addNewIdentifer*(gState: State, name: string, override = false): bool =
  if override or name notin gState.symOverride:
    let
      nimName = name[0] & name[1 .. ^1].replace("_", "").toLowerAscii

    if gState.identifiers.hasKey(nimName):
      doAssert name == gState.identifiers[nimName],
        &"Identifier '{name}' is a stylistic duplicate of identifier " &
        &"'{gState.identifiers[nimName]}', use 'cPlugin:onSymbol()' to rename"
      result = false
    else:
      gState.identifiers[nimName] = name
      result = true

# Overrides related

proc getOverride*(gState: State, name: string, kind: NimSymKind): string =
  # Get cOverride for identifier `name` of `kind` if defined
  doAssert name.nBl, "Blank identifier error"

  if gState.onSymbolOverride != nil:
    var
      nname = gState.getIdentifier(name, kind, "IgnoreSkipSymbol")
      sym = Symbol(name: nname, kind: kind)
    if nname.nBl:
      gState.onSymbolOverride(sym)

      if sym.override.nBl and gState.addNewIdentifer(nname, override = true):
        result = sym.override

        if kind != nskProc:
          result = "  " & result.replace("\n", "\n ")

proc getOverrideFinal*(gState: State, kind: NimSymKind): string =
  # Get all unused cOverride symbols of `kind`
  let
    typ = $kind

  if gState.onSymbolOverrideFinal != nil:
    for i in gState.onSymbolOverrideFinal(typ):
      result &= "\n" & gState.getOverride(i, kind)

proc getKeyword*(kind: NimSymKind): string =
  # Convert `kind` into a Nim keyword
  # cOverride procs already include `proc` keyword
  result = ($kind).replace("nsk", "").toLowerAscii()

proc getCurrentHeader*(fullpath: string): string =
  ("header" & fullpath.splitFile().name.multiReplace([(".", ""), ("-", "")]))

proc getPreprocessor*(gState: State, fullpath: string) =
  var
    cmts = if gState.noComments: "" else: "-CC"
    cmd = &"""{getCompiler()} -E {cmts} -dD {getGccModeArg(gState.mode)} -w """

    rdata: seq[string]
    start = false
    sfile = fullpath.sanitizePath(noQuote = true)

    sfileName = sfile.extractFilename()
    pDir = sfile.expandFilename().parentDir()
    includeDirs: seq[string]

  for inc in gState.includeDirs:
    cmd &= &"-I{inc.sanitizePath} "
    includeDirs.add inc.absolutePath().sanitizePath(noQuote = true)

  for def in gState.defines:
    cmd &= &"-D{def} "

  # Remove gcc special calls
  if defined(posix):
    cmd &= "-D__attribute__\\(x\\)= "
  else:
    cmd &= "-D__attribute__(x)= "

  cmd &= "-D__restrict= -D__extension__= -D__inline__=inline -D__inline=inline "

  # https://github.com/tree-sitter/tree-sitter-c/issues/43
  cmd &= "-D_Noreturn= "

  cmd &= &"{fullpath.sanitizePath}"

  # Include content only from file
  for line in execAction(cmd).output.splitLines():
    # We want to keep blank lines here for comment processing
    if line.len > 1 and line[0 .. 1] == "# ":
      start = false
      let
        saniLine = line.sanitizePath(noQuote = true)
      if sfile in saniLine or
        (DirSep notin saniLine and sfileName in saniLine):
        start = true
      elif gState.recurse:
        if pDir.Bl or pDir in saniLine:
          start = true
        else:
          for inc in includeDirs:
            if inc in saniLine:
              start = true
              break
    else:
      if start:
        if "#undef" in line:
          continue
        rdata.add line
  gState.code = rdata.join("\n")

converter toString*(kind: Kind): string =
  return case kind:
    of exactlyOne:
      ""
    of oneOrMore:
      "+"
    of zeroOrMore:
      "*"
    of zeroOrOne:
      "?"
    of orWithNext:
      "!"

converter toKind*(kind: string): Kind =
  return case kind:
    of "+":
      oneOrMore
    of "*":
      zeroOrMore
    of "?":
      zeroOrOne
    of "!":
      orWithNext
    else:
      exactlyOne

proc getNameKind*(name: string): tuple[name: string, kind: Kind, recursive: bool] =
  if name[0] == '^':
    result.recursive = true
    result.name = name[1 .. ^1]
  else:
    result.name = name
  result.kind = $name[^1]

  if result.kind != exactlyOne:
    result.name = result.name[0 .. ^2]

proc getRegexForAstChildren*(ast: ref Ast): string =
  result = "^"
  for i in 0 .. ast.children.len-1:
    let
      kind: string = ast.children[i].kind
      begin = if result[^1] == '|': "" else: "(?:"
    case kind:
      of "!":
        result &= &"{begin}{ast.children[i].name}|"
      else:
        result &= &"{begin}{ast.children[i].name}){kind}"
  result &= "$"

proc getAstChildByName*(ast: ref Ast, name: string): ref Ast =
  for i in 0 .. ast.children.len-1:
    if name in ast.children[i].name.split("|"):
      return ast.children[i]

  if ast.children.len == 1 and ast.children[0].name == ".":
    return ast.children[0]

proc getNimExpression*(gState: State, expr: string, name = ""): string =
  # Convert C/C++ expression into Nim - cast identifiers to `name` if specified
  var
    clean = expr.multiReplace([("\n", " "), ("\r", "")])
    ident = ""
    gen = ""
    hex = false

  for i in 0 .. clean.len:
    if i != clean.len:
      if clean[i] in IdentChars:
        if clean[i] in Digits and ident.Bl:
          # Identifiers cannot start with digits
          gen = $clean[i]
        elif clean[i] in HexDigits and hex == true:
          # Part of a hex number
          gen = $clean[i]
        elif i > 0 and i < clean.len-1 and clean[i] in ['x', 'X'] and
              clean[i-1] == '0' and clean[i+1] in HexDigits:
          # Found a hex number
          gen = $clean[i]
          hex = true
        else:
          # Part of an identifier
          ident &= clean[i]
          hex = false
      else:
        gen = (block:
          if (i == 0 or clean[i-1] != '\'') or
            (i == clean.len - 1 or clean[i+1] != '\''):
              # If unquoted, convert logical ops to Nim
              case clean[i]
              of '^': " xor "
              of '&': " and "
              of '|': " or "
              of '~': " not "
              else: $clean[i]
          else:
            $clean[i]
        )
        hex = false

    if i == clean.len or gen.nBl:
      # Process identifier
      if ident.nBl:
        # Issue #178
        if ident != "_":
          ident = gState.getIdentifier(ident, nskConst, name)
        if name.nBl and ident in gState.constIdentifiers:
          ident = ident & "." & name
        result &= ident
        ident = ""
      result &= gen
      gen = ""

  # Convert shift ops to Nim
  result = result.multiReplace([
    ("<<", " shl "), (">>", " shr ")
  ])

proc getComments*(gState: State, strip = false): string =
  if not gState.noComments and gState.commentStr.nBl:
    result = "\n" & gState.commentStr
    if strip:
      result = result.replace("\n  ", "\n")
    gState.commentStr = ""

# Plugin related

proc dll*(path: string): string =
  let
    (dir, name, _) = path.splitFile()

  result = dir / (DynlibFormat % name)

proc loadPlugin*(gState: State, sourcePath: string) =
  doAssert fileExists(sourcePath), "Plugin file does not exist: " & sourcePath

  let
    pdll = sourcePath.dll
  if not fileExists(pdll) or
    sourcePath.getLastModificationTime() > pdll.getLastModificationTime():
    let
      # Get Nim configuration flags if not already specified in a .cfg file
      flags =
        if fileExists(sourcePath & ".cfg"): ""
        else: getNimConfigFlags(getCurrentDir())

      # Always set output to same directory as source, prevents override
      outflags = &"--out:\"{pdll}\""

      # Compile plugin as library with `markAndSweep` GC
      cmd = &"{gState.nim} c --app:lib --gc:markAndSweep {flags} {outflags} {sourcePath.sanitizePath}"

    discard execAction(cmd)
  doAssert fileExists(pdll), "No plugin binary generated for " & sourcePath

  let lib = loadLib(pdll)
  doAssert lib != nil, "Plugin $1 compiled to $2 failed to load" % [sourcePath, pdll]

  gState.onSymbol = cast[OnSymbol](lib.symAddr("onSymbol"))

  gState.onSymbolOverride = cast[OnSymbol](lib.symAddr("onSymbolOverride"))

  gState.onSymbolOverrideFinal = cast[OnSymbolOverrideFinal](lib.symAddr("onSymbolOverrideFinal"))

# Misc toast helpers

proc getSplitComma*(joined: seq[string]): seq[string] =
  for i in joined:
    result = result.concat(i.split(","))

proc expandSymlinkAbs*(path: string): string =
  try:
    result = path.expandFilename().normalizedPath()
  except:
    result = path
