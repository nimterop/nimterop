import dynlib, macros, os, sequtils, sets, strformat, strutils, tables, times

import regex

import compiler/[ast, idents, lineinfos, msgs, pathutils, renderer]

import "."/[build, globals, plugin, treesitter/api]

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

# Identifier related

proc checkIdentifier(name, kind, parent, origName: string) =
  let
    parentStr = if parent.nBl: parent & ":" else: ""

  if name.nBl:
    let
      origStr = if name != origName: &", originally '{origName}' before 'cPlugin:onSymbol()', still" else: ""
      errmsg = &"Identifier '{parentStr}{name}' ({kind}){origStr} contains"

    doAssert name[0] != '_' and name[^1] != '_', errmsg & " leading/trailing underscores '_'"

    doAssert (not name.contains("__")): errmsg & " consecutive underscores '_'"

  if parent.nBl:
    doAssert name.nBl, &"Blank identifier, originally '{parentStr}{origName}' ({kind}), cannot be empty"

proc getIdentifier*(nimState: NimState, name: string, kind: NimSymKind, parent=""): string =
  doAssert name.nBl, "Blank identifier error"

  if name notin nimState.gState.symOverride or parent.nBl:
    if nimState.gState.onSymbol != nil:
      # Use onSymbol from plugin provided by user
      var
        sym = Symbol(name: name, parent: parent, kind: kind)
      nimState.gState.onSymbol(sym)

      result = sym.name
    else:
      result = name

      # Strip out --prefix from CLI if specified
      for str in nimState.gState.prefix:
        if result.startsWith(str):
          result = result[str.len .. ^1]

      # Strip out --suffix from CLI if specified
      for str in nimState.gState.suffix:
        if result.endsWith(str):
          result = result[0 .. ^(str.len+1)]

    checkIdentifier(result, $kind, parent, name)

    if result in gReserved or (result == "object" and kind != nskType):
      # Enclose in backticks since Nim reserved word
      result = &"`{result}`"
  else:
    # Skip identifier since in symOverride
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

# Overrides related

proc getOverride*(nimState: NimState, name: string, kind: NimSymKind): string =
  # Get cOverride for identifier `name` of `kind` if defined
  doAssert name.nBl, "Blank identifier error"

  if nimState.gState.onSymbolOverride != nil:
    var
      nname = nimState.getIdentifier(name, kind, "Override")
      sym = Symbol(name: nname, kind: kind)
    if nname.nBl:
      nimState.gState.onSymbolOverride(sym)

      if sym.override.nBl and nimState.addNewIdentifer(nname, override = true):
        result = sym.override

        if kind != nskProc:
          result = result.replace(re"(?m)^(.*?)$", "  $1")

proc getOverrideFinal*(nimState: NimState, kind: NimSymKind): string =
  # Get all unused cOverride symbols of `kind`
  let
    typ = $kind

  if nimState.gState.onSymbolOverrideFinal != nil:
    for i in nimState.gState.onSymbolOverrideFinal(typ):
      result &= "\n" & nimState.getOverride(i, kind)

proc getKeyword*(kind: NimSymKind): string =
  # Convert `kind` into a Nim keyword
  # cOverride procs already include `proc` keyword
  result = ($kind).replace("nsk", "").toLowerAscii()

# TSNode shortcuts

proc isNil*(node: TSNode): bool =
  node.tsNodeIsNull()

proc len*(node: TSNode): int =
  if not node.isNil:
    result = node.tsNodeNamedChildCount().int

proc `[]`*(node: TSNode, i: SomeInteger): TSNode =
  if i < node.len:
    result = node.tsNodeNamedChild(i.uint32)

proc getName*(node: TSNode): string {.inline.} =
  if not node.isNil:
    return $node.tsNodeType()

proc getNodeVal*(gState: State, node: TSNode): string =
  if not node.isNil:
    return gState.code[node.tsNodeStartByte() .. node.tsNodeEndByte()-1].strip()

proc getNodeVal*(nimState: NimState, node: TSNode): string =
  nimState.gState.getNodeVal(node)

proc getAtom*(node: TSNode): TSNode =
  if not node.isNil:
    # Get child node which is topmost atom
    if node.getName() in gAtoms:
      return node
    elif node.len != 0:
      if node[0].getName() == "type_qualifier":
        # Skip const, volatile
        if node.len > 1:
          return node[1].getAtom()
        else:
          return
      else:
        return node[0].getAtom()

proc getStartAtom*(node: TSNode): int =
  if not node.isNil:
    # Skip const, volatile and other type qualifiers
    for i in 0 .. node.len - 1:
      if node[i].getAtom().getName() notin gAtoms:
        result += 1
      else:
        break

proc getXCount*(node: TSNode, ntype: string, reverse = false): int =
  if not node.isNil:
    # Get number of ntype nodes nested in tree
    var
      cnode = node
    while ntype in cnode.getName():
      result += 1
      if reverse:
        cnode = cnode.tsNodeParent()
      else:
        if cnode.len != 0:
          if cnode[0].getName() == "type_qualifier":
            # Skip const, volatile
            if cnode.len > 1:
              cnode = cnode[1]
            else:
              break
          else:
            cnode = cnode[0]
        else:
          break

proc getPtrCount*(node: TSNode, reverse = false): int =
  node.getXCount("pointer_declarator")

proc getArrayCount*(node: TSNode, reverse = false): int =
  node.getXCount("array_declarator")

proc getDeclarator*(node: TSNode): TSNode =
  if not node.isNil:
    # Return if child is a function or array declarator
    if node.getName() in ["function_declarator", "array_declarator"]:
      return node
    elif node.len != 0:
      return node[0].getDeclarator()

proc getVarargs*(node: TSNode): bool =
  # Detect ... and add {.varargs.}
  #
  # `node` is the param list
  #
  # ... is an unnamed node, second last node and ) is last node
  let
    nlen = node.tsNodeChildCount()
  if nlen > 1:
    let
      nval = node.tsNodeChild(nlen - 2).getName()
    if nval == "...":
      result = true

proc firstChildInTree*(node: TSNode, ntype: string): TSNode =
  # Search for node type in tree - first children
  var
    cnode = node
  while not cnode.isNil:
    if cnode.getName() == ntype:
      return cnode
    cnode = cnode[0]

proc anyChildInTree*(node: TSNode, ntype: string): TSNode =
  # Search for node type anywhere in tree - depth first
  var
    cnode = node
  while not cnode.isNil:
    if cnode.getName() == ntype:
      return cnode
    for i in 0 ..< cnode.len:
      let
        ccnode = cnode[i].anyChildInTree(ntype)
      if not ccnode.isNil:
        return ccnode
    if cnode != node:
      cnode = cnode.tsNodeNextNamedSibling()
    else:
      break

proc mostNestedChildInTree*(node: TSNode): TSNode =
  # Search for the most nested child of node's type in tree
  var
    cnode = node
    ntype = cnode.getName()
  while not cnode.isNil and cnode.len != 0 and cnode[0].getName() == ntype:
    cnode = cnode[0]
  result = cnode

proc inChildren*(node: TSNode, ntype: string): bool =
  # Search for node type in immediate children
  result = false
  for i in 0 ..< node.len:
    if (node[i]).getName() == ntype:
      result = true
      break

proc getLineCol*(gState: State, node: TSNode): tuple[line, col: int] =
  # Get line number and column info for node
  result.line = 1
  result.col = 1
  for i in 0 .. node.tsNodeStartByte().int-1:
    if gState.code[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1

proc getTSNodeNamedChildCountSansComments*(node: TSNode): int =
  for i in 0 ..< node.len:
    if node.getName() != "comment":
      result += 1

proc getPxName*(node: TSNode, offset: int): string =
  # Get the xth (grand)parent of the node
  var
    np = node
    count = 0

  while not np.isNil and count < offset:
    np = np.tsNodeParent()
    count += 1

  if count == offset and not np.isNil:
    return np.getName()

proc printLisp*(gState: State, root: TSNode): string =
  var
    node = root
    nextnode: TSNode
    depth = 0

  while true:
    if not node.isNil and depth > -1:
      result &= spaces(depth)
      let
        (line, col) = gState.getLineCol(node)
      result &= &"({$node.tsNodeType()} {line} {col} {node.tsNodeEndByte() - node.tsNodeStartByte()}"
      let
        val = gState.getNodeVal(node)
      if "\n" notin val and " " notin val:
        result &= &" \"{val}\""
    else:
      break

    if node.tsNodeNamedChildCount() != 0:
      result &= "\n"
      nextnode = node.tsNodeNamedChild(0)
      depth += 1
    else:
      result &= ")\n"
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.isNil:
      while true:
        node = node.tsNodeParent()
        depth -= 1
        if depth == -1:
          break
        result &= spaces(depth) & ")\n"
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().isNil:
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc getCommented*(str: string): string =
  "\n# " & str.strip().replace("\n", "\n# ")

proc printTree*(nimState: NimState, pnode: PNode, offset = ""): string =
  if nimState.gState.debug and pnode.kind != nkNone:
    result &= "\n# " & offset & $pnode.kind & "("
    case pnode.kind
    of nkCharLit:
      result &= "'" & pnode.intVal.char & "')"
    of nkIntLit..nkUInt64Lit:
      result &= $pnode.intVal & ")"
    of nkFloatLit..nkFloat128Lit:
      result &= $pnode.floatVal & ")"
    of nkStrLit..nkTripleStrLit:
      result &= "\"" & pnode.strVal & "\")"
    of nkSym:
      result &= $pnode.sym & ")"
    of nkIdent:
      result &= "\"" & $pnode.ident.s & "\")"
    else:
      if pnode.sons.len != 0:
        for i in 0 ..< pnode.sons.len:
          result &= nimState.printTree(pnode.sons[i], offset & " ")
          if i != pnode.sons.len - 1:
            result &= ","
        result &= "\n# " & offset & ")"
      else:
        result &= ")"
    if offset.len == 0:
      result &= "\n"

proc printDebug*(nimState: NimState, node: TSNode) =
  if nimState.gState.debug:
    necho ("Input => " & nimState.getNodeVal(node)).getCommented() & "\n" &
          nimState.gState.printLisp(node).getCommented()

proc printDebug*(nimState: NimState, pnode: PNode) =
  if nimState.gState.debug:
    necho ("Output => " & $pnode).getCommented() & "\n" &
          nimState.printTree(pnode)

# Compiler shortcuts

proc getDefaultLineInfo*(nimState: NimState): TLineInfo =
  result = newLineInfo(nimState.config, nimState.sourceFile.AbsoluteFile, 0, 0)

proc getLineInfo*(nimState: NimState, node: TSNode): TLineInfo =
  # Get Nim equivalent line:col info from node
  let
    (line, col) = nimState.gState.getLineCol(node)

  result = newLineInfo(nimState.config, nimState.sourceFile.AbsoluteFile, line, col)

proc getIdent*(nimState: NimState, name: string, info: TLineInfo, exported = true): PNode =
  if name.nBl:
    # Get ident PNode for name + info
    let
      exp = getIdent(nimState.identCache, "*")
      ident = getIdent(nimState.identCache, name)

    if exported:
      result = newNode(nkPostfix)
      result.add newIdentNode(exp, info)
      result.add newIdentNode(ident, info)
    else:
      result = newIdentNode(ident, info)

proc getIdent*(nimState: NimState, name: string): PNode =
  nimState.getIdent(name, nimState.getDefaultLineInfo(), exported = false)

proc getIdentName*(node: PNode): string =
  if not node.isNil:
    for i in 0 ..< node.len:
      if node[i].kind == nkIdent and $node[i] != "*":
        result = $node[i]
    if result.Bl and node.len > 0:
      result = node[0].getIdentName()

proc getNameInfo*(nimState: NimState, node: TSNode, kind: NimSymKind, parent = ""):
  tuple[name, origname: string, info: TLineInfo] =
  # Shortcut to get identifier name and info (node value and line:col)
  result.origname = nimState.getNodeVal(node)
  result.name = nimState.getIdentifier(result.origname, kind, parent)
  if result.name.nBl:
    if kind == nskType:
      result.name = result.name.getType()
    result.info = nimState.getLineInfo(node)

proc getCurrentHeader*(fullpath: string): string =
  ("header" & fullpath.splitFile().name.multiReplace([(".", ""), ("-", "")]))

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

proc getPreprocessor*(gState: State, fullpath: string): string =
  var
    cmts = if gState.nocomments: "" else: "-CC"
    cmd = &"""{getCompiler()} -E {cmts} -dD {getGccModeArg(gState.mode)} -w """

    rdata: seq[string] = @[]
    start = false
    sfile = fullpath.sanitizePath(noQuote = true)

  for inc in gState.includeDirs:
    cmd &= &"-I{inc.sanitizePath} "

  for def in gState.defines:
    cmd &= &"-D{def} "

  cmd &= &"{fullpath.sanitizePath}"

  # Include content only from file
  for line in execAction(cmd).output.splitLines():
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
          if pDir.Bl or pDir in saniLine:
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
          rdata.add line
  return rdata.join("\n").
    replace("__restrict", "").
    replace(re"__attribute__[ ]*\(\(.*?\)\)([ ,;])", "$1").
    removeStatic()

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

proc getNimExpression*(nimState: NimState, expr: string, name = ""): string =
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
          ident = nimState.getIdentifier(ident, nskConst, name)
        if name.nBl and ident in nimState.constIdentifiers:
          ident = ident & "." & name
        result &= ident
        ident = ""
      result &= gen
      gen = ""

  # Convert shift ops to Nim
  result = result.multiReplace([
    ("<<", " shl "), (">>", " shr ")
  ])

proc getSplitComma*(joined: seq[string]): seq[string] =
  for i in joined:
    result = result.concat(i.split(","))

template includeHeader*(nimState: NimState): bool =
  nimState.gState.dynlib.Bl and nimState.gState.includeHeader

proc getComments*(nimState: NimState, strip = false): string =
  if not nimState.gState.nocomments and nimState.commentStr.nBl:
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
    result = path.expandSymlink().absolutePath(path.parentDir()).normalizedPath()
  except:
    result = path
