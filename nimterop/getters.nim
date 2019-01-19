import macros, os, sets, strformat, strutils, tables

import regex

import "."/[git, globals, treesitter/runtime]

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

const gTypeMap = {
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

  # int
  "int": "cint",
  "signed": "cint",
  "signed int": "cint",
  "ssize_t": "cint",
  "unsigned": "cuint",
  "unsigned int": "cuint",
  "size_t": "cuint",

  # long
  "long": "clong",
  "long int": "clong",
  "signed long": "clong",
  "signed long int": "clong",
  "off_t": "clong",
  "unsigned long": "culong",
  "unsigned long int": "culong",

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

  # misc
  "time_t": "int32",
  "ptrdiff_t": "ByteAddress"
}.toTable()

proc sanitizePath*(path: string): string =
  path.multiReplace([("\\\\", $DirSep), ("\\", $DirSep), ("//", $DirSep)])

proc getType*(str: string): string =
  if str == "void":
    return "object"

  result = str.strip(chars={'_'}).
    replace(re"([u]?int[\d]+)_t", "$1").
    replace(re"([u]?int)ptr_t", "ptr $1")

  if gTypeMap.hasKey(result):
    result = gTypeMap[result]

proc getIdentifier*(str: string): string =
  result = str.strip(chars={'_'}).replace(re"_+", "_")

  if result in gReserved:
    result = &"`{result}`"

proc getUniqueIdentifier*(existing: HashSet[string], prefix = ""): string =
  var
    name = prefix & "_" & gStateRT.sourceFile.extractFilename().multiReplace([(".", ""), ("-", "")])
    nimName = name.replace("_", "").toLowerAscii
    count = 1

  while (nimName & $count) in existing:
    count += 1

  return name & $count

proc addNewIdentifer*(existing: var HashSet[string], name: string): bool =
  return not existing.containsOrIncl(name.replace("_", "").toLowerAscii)

proc getPtrType*(str: string): string =
  result = case str:
    of "ptr cchar":
      "cstring"
    of "ptr object":
      "pointer"
    else:
      str

proc getLit*(str: string): string =
  if str.contains(re"^[\-]?[\d]+$") or
    str.contains(re"^[\-]?[\d]*\.[\d]+$") or
    str.contains(re"^0x[\d]+$"):
    return str

proc getNodeVal*(node: TSNode): string =
  return gStateRT.code[node.tsNodeStartByte() .. node.tsNodeEndByte()-1].strip()

proc getNodeValIf*(node: TSNode, esym: string): string =
  if esym != $node.tsNodeType():
    return

  return node.getNodeVal()

proc getLineCol*(node: TSNode): tuple[line, col: int] =
  result.line = 1
  result.col = 1
  for i in 0 .. node.tsNodeStartByte().int-1:
    if gStateRT.code[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1

proc getCurrentHeader*(fullpath: string): string =
  ("header" & fullpath.splitFile().name.replace(re"[-.]+", ""))

proc removeStatic(content: string): string =
  ## Replace static function bodies with a semicolon and commented
  ## out body
  return content.replace(
    re"(?ms)static inline(.*?\))(\s*\{(\s*?.*?$)*?[\n\r]\})",
    proc (m: RegexMatch, s: string): string =
      let funcDecl = s[m.group(0)[0]]
      let body = s[m.group(1)[0]].strip()
      result = ""

      result.add("$#;" % [funcDecl])
      result.add(body.replace(re"(?m)^(.*\n?)", "//$1"))
  )

proc getPreprocessor*(fullpath: string, mode = "cpp"): string =
  var
    mmode = if mode == "cpp": "c++" else: mode
    cmd = &"gcc -E -dD -x{mmode} -w "

    rdata: seq[string] = @[]
    start = false
    sfile = fullpath.sanitizePath

  for inc in gStateRT.includeDirs:
    cmd &= &"-I\"{inc}\" "

  for def in gStateRT.defines:
    cmd &= &"-D{def} "

  cmd &= &"\"{fullpath}\""

  # Include content only from file
  for line in execAction(cmd).splitLines():
    if line.strip() != "":
      if line.len > 1 and line[0 .. 1] == "# ":
        start = false
        let
          saniLine = line.sanitizePath
        if sfile in saniLine:
          start = true
        elif not ("\\" in line) and not ("/" in line) and extractFilename(sfile) in line:
          start = true
        elif gStateRT.recurse:
          if sfile.parentDir() in saniLine:
            start = true
          else:
            for inc in gStateRT.includeDirs:
              if inc.absolutePath().sanitizePath in saniLine:
                start = true
                break
          if start:
            rdata.add(&"// {line}")
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

proc getPName*(node: TSNode): string =
  if not node.tsNodeIsNull():
    let
      nparent = node.tsNodeParent()
    if not nparent.tsNodeIsNull():
      return $nparent.tsNodeType()

proc isPName*(node: TSNode, name: string): bool =
  return node.getPName() == name

proc isPPName*(node: TSNode, name: string): bool =
  if node.getPName().len != 0:
    return node.tsNodeParent().isPName(name)
