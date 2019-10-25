import dynlib, macros, os, sequtils, sets, strformat, strutils, tables, times

import regex

import "."/[build, compat, globals, plugin, treesitter/api]

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
yield""".split(Whitespace).toSet()

const gTypeMap* = {
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
  "long double": "clongdouble"
}.toTable()

proc getType*(str: string): string =
  if str == "void":
    return "object"

  result = str.strip(chars={'_'}).
    replace(re"\s+", " ").
    replace(re"^([u]?int[\d]+)_t$", "$1").
    replace(re"^([u]?int)ptr_t$", "ptr $1")

  if gTypeMap.hasKey(result):
    result = gTypeMap[result]

proc checkIdentifier(name, kind, parent, origName: string) =
  let
    parentStr = if parent.nBl: parent & ":" else: ""

  if name.len != 0:
    let
      origStr = if name != origName: &", originally '{origName}' before 'cPlugin:onSymbol()', still" else: ""
      errmsg = &"Identifier '{parentStr}{name}' ({kind}){origStr} contains"

    doAssert name[0] != '_' and name[^1] != '_', errmsg & " leading/trailing underscores '_'"

    doAssert (not name.contains(re"_[_]+")): errmsg & " more than one consecutive underscore '_'"

  if parent.nBl:
    doAssert name.nBl, &"Blank identifier, originally '{parentStr}{name}' ({kind}), cannot be empty"

proc getIdentifier*(nimState: NimState, name: string, kind: NimSymKind, parent=""): string =
  doAssert name.len != 0, "Blank identifier error"

  if name notin nimState.gState.symOverride or parent.nBl:
    if nimState.gState.onSymbol != nil:
      var
        sym = Symbol(name: name, parent: parent, kind: kind)
      nimState.gState.onSymbol(sym)

      result = sym.name
    else:
      result = name

    checkIdentifier(result, $kind, parent, name)

    if result in gReserved or (result == "object" and kind != nskType):
      result = &"`{result}`"
  else:
    result = ""

proc getUniqueIdentifier*(nimState: NimState, prefix = ""): string =
  var
    name = prefix & "_" & nimState.sourceFile.extractFilename().multiReplace([(".", ""), ("-", "")])
    nimName = name[0] & name[1 .. ^1].replace("_", "").toLowerAscii
    count = 1

  while (nimName & $count) in nimState.identifiers:
    count += 1

  return name & $count

proc addNewIdentifer*(nimState: NimState, name: string, override = false): bool =
  if override or name notin nimState.gState.symOverride:
    let
      nimName = name[0] & name[1 .. ^1].replace("_", "").toLowerAscii

    if nimState.identifiers.hasKey(nimName):
      doAssert name == nimState.identifiers[nimName],
        &"Identifier '{name}' is a stylistic duplicate of identifier " &
        &"'{nimState.identifiers[nimName]}', use 'cPlugin:onSymbol()' to rename"
      result = false
    else:
      nimState.identifiers[nimName] = name
      result = true

proc getOverride*(nimState: NimState, name: string, kind: NimSymKind): string =
  doAssert name.len != 0, "Blank identifier error"

  if nimState.gState.onSymbolOverride != nil:
    var
      nname = nimState.getIdentifier(name, kind, "Override")
      sym = Symbol(name: nname, kind: kind)
    if nname.nBl:
      nimState.gState.onSymbolOverride(sym)

      if sym.override.len != 0 and nimState.addNewIdentifer(nname, override = true):
        result = sym.override

        if kind != nskProc:
          result = result.replace(re"(?m)^(.*?)$", "  $1")

proc getOverrideFinal*(nimState: NimState, kind: NimSymKind): string =
  let
    typ = $kind

  if nimState.gState.onSymbolOverrideFinal != nil:
    for i in nimState.gState.onSymbolOverrideFinal(typ):
      result &= "\n" & nimState.getOverride(i, kind)

proc getPtrType*(str: string): string =
  result = case str:
    of "ptr cchar":
      "cstring"
    of "ptr ptr cchar":
      "ptr cstring"
    of "ptr object":
      "pointer"
    of "ptr ptr object":
      "ptr pointer"
    else:
      str

proc getLit*(str: string): string =
  let
    str = str.replace(re"//.*?$", "").replace(re"/\*.*?\*/", "").strip()

  if str.contains(re"^[\-]?[\d]+$") or
    str.contains(re"^[\-]?[\d]*\.[\d]+$") or
    str.contains(re"^0x[\d]+$"):
    return str

proc getNodeVal*(nimState: NimState, node: TSNode): string =
  return nimState.gState.code[node.tsNodeStartByte() .. node.tsNodeEndByte()-1].strip()

proc getLineCol*(gState: State, node: TSNode): tuple[line, col: int] =
  result.line = 1
  result.col = 1
  for i in 0 .. node.tsNodeStartByte().int-1:
    if gState.code[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1

proc getCurrentHeader*(fullpath: string): string =
  ("header" & fullpath.splitFile().name.replace(re"[-.]+", ""))

proc removeStatic(content: string): string =
  ## Replace static function bodies with a semicolon and commented
  ## out body
  return content.replace(
    re"(?msU)static inline ([^)]+\))([^}]+\})",
    proc (m: RegexMatch, s: string): string =
      let funcDecl = s[m.group(0)[0]]
      let body = s[m.group(1)[0]].strip()
      result = ""

      result.add("$#;" % [funcDecl])
      result.add(body.replace(re"(?m)^(.*\n?)", "//$1"))
  )

proc getPreprocessor*(gState: State, fullpath: string, mode = "cpp"): string =
  var
    mmode = if mode == "cpp": "c++" else: mode
    cmd = &"""{getCompiler()} -E -CC -dD -x{mmode} -w """

    rdata: seq[string] = @[]
    start = false
    sfile = fullpath.sanitizePath(noQuote = true)

  for inc in gState.includeDirs:
    cmd &= &"-I{inc.sanitizePath} "

  for def in gState.defines:
    cmd &= &"-D{def} "

  cmd &= &"{fullpath.sanitizePath}"

  # Include content only from file
  for line in execAction(cmd).splitLines():
    if line.strip() != "":
      if line.len > 1 and line[0 .. 1] == "# ":
        start = false
        let
          saniLine = line.sanitizePath(noQuote = true)
        if sfile in saniLine:
          start = true
        elif not ("\\" in line) and not ("/" in line) and extractFilename(sfile) in line:
          start = true
        elif gState.recurse:
          let
            pDir = sfile.expandFilename().parentDir().sanitizePath(noQuote = true)
          if pDir.len == 0 or pDir in saniLine:
            start = true
          else:
            for inc in gState.includeDirs:
              if inc.absolutePath().sanitizePath(noQuote = true) in saniLine:
                start = true
                break
      else:
        if start:
          if "#undef" in line:
            continue
          rdata.add(
            line.
              replace("__restrict", "").
              replace(re"__attribute__[ ]*\(\(.*?\)\)([ ,;])", "$1")
          )
  return rdata.join("\n").removeStatic()

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

proc getTSNodeNamedChildCountSansComments*(node: TSNode): int =
  if node.tsNodeNamedChildCount() != 0:
    for i in 0 .. node.tsNodeNamedChildCount()-1:
      if $node.tsNodeType() != "comment":
        result += 1

proc getTSNodeNamedChildNames*(node: TSNode): seq[string] =
  if node.tsNodeNamedChildCount() != 0:
    for i in 0 .. node.tsNodeNamedChildCount()-1:
      let
        name = $node.tsNodeNamedChild(i).tsNodeType()

      if name != "comment":
        result.add(name)

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

proc getPxName*(node: TSNode, offset: int): string =
  var
    np = node
    count = 0

  while not np.tsNodeIsNull() and count < offset:
    np = np.tsNodeParent()
    count += 1

  if count == offset and not np.tsNodeIsNull():
    return $np.tsNodeType()

proc getNimExpression*(nimState: NimState, expr: string): string =
  var
    clean = expr.multiReplace([("\n", " "), ("\r", "")])
    ident = ""
    gen = ""
    hex = false

  for i in 0 .. clean.len:
    if i != clean.len:
      if clean[i] == '_' and ident.len == 0:
        gen = $clean[i]
      elif clean[i] in IdentChars:
        if clean[i] in Digits and ident.len == 0:
          gen = $clean[i]
        elif clean[i] in HexDigits and hex == true:
          gen = $clean[i]
        elif i > 0 and i < clean.len-1 and clean[i] in ['x', 'X'] and
              clean[i-1] == '0' and clean[i+1] in HexDigits:
          gen = $clean[i]
          hex = true
        else:
          ident &= clean[i]
          hex = false
      else:
        gen = (block:
          if (i == 0 or clean[i-1] != '\'') or
            (i == clean.len - 1 or clean[i+1] != '\''):
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

    if i == clean.len or gen.len != 0:
      if ident.len != 0:
        ident = nimState.getIdentifier(ident, nskConst)
        result &= ident
        ident = ""
      result &= gen
      gen = ""

  result = result.multiReplace([
    ("<<", " shl "), (">>", " shr ")
  ])

proc getSplitComma*(joined: seq[string]): seq[string] =
  for i in joined:
    result = result.concat(i.split(","))

proc getHeader*(nimState: NimState): string =
  result =
    if nimState.gState.dynlib.len == 0:
      &", header: {nimState.currentHeader}"
    else:
      ""

proc getDynlib*(nimState: NimState): string =
  result =
    if nimState.gState.dynlib.len != 0:
      &", dynlib: {nimState.gState.dynlib}"
    else:
      ""

proc getImportC*(nimState: NimState, origName, nimName: string): string =
  if nimName != origName:
    result = &"importc: \"{origName}\"{nimState.getHeader()}"
  else:
    result = nimState.impShort

proc getPragma*(nimState: NimState, pragmas: varargs[string]): string =
  result = ""
  for pragma in pragmas.items():
    if pragma.len != 0:
      result &= pragma & ", "
  if result.len != 0:
    result = " {." & result[0 .. ^3] & ".}"

  result = result.replace(nimState.impShort & ", cdecl", nimState.impShort & "C")

  let
    dy = nimState.getDynlib()

  if ", cdecl" in result and dy.len != 0:
    result = result.replace(".}", dy & ".}")

proc getComments*(nimState: NimState, strip = false): string =
  if not nimState.gState.nocomments and nimState.commentStr.len != 0:
    result = "\n" & nimState.commentStr
    if strip:
      result = result.replace("\n  ", "\n")
    nimState.commentStr = ""

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
    discard execAction(&"{gState.nim.sanitizePath} c --app:lib {sourcePath.sanitizePath}")
  doAssert fileExists(pdll), "No plugin binary generated for " & sourcePath

  let lib = loadLib(pdll)
  doAssert lib != nil, "Plugin $1 compiled to $2 failed to load" % [sourcePath, pdll]

  gState.onSymbol = cast[OnSymbol](lib.symAddr("onSymbol"))

  gState.onSymbolOverride = cast[OnSymbol](lib.symAddr("onSymbolOverride"))

  gState.onSymbolOverrideFinal = cast[OnSymbolOverrideFinal](lib.symAddr("onSymbolOverrideFinal"))

proc expandSymlinkAbs*(path: string): string =
  try:
    result = path.expandSymlink().absolutePath(path.parentDir()).myNormalizedPath()
  except:
    result = path
