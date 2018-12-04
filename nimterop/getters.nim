import macros, os, strformat, strutils

import regex

import treesitter/runtime

import git, globals

proc sanitizePath*(path: string): string =
  path.multiReplace([("\\\\", $DirSep), ("\\", $DirSep), ("//", $DirSep)])

proc getIdentifier*(str: string): string =
  result = str.strip(chars={'_'})

proc getType*(str: string): string =
  if str == "void":
    return "object"

  result = str.strip(chars={'_'}).
    multiReplace([
      ("unsigned ", "cu"),
      ("double ", "cdouble"),
      ("long ", "clong"),
    ]).
    replace(re"([u]?int[\d]+)_t", "$1")

  case result:
    of "long":
      result = "clong"
    of "double":
      result = "cdouble"

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

proc getGccPaths*(mode = "c"): string =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode

  return staticExec("gcc -Wp,-v -x" & mmode & " " & nul)

proc getPreprocessor*(fullpath: string, mode = "cpp"): string =
  var
    mmode = if mode == "cpp": "c++" else: mode
    cmd = &"gcc -E -dD -x{mmode} "

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
      if line[0] == '#' and not line.contains("#pragma") and not line.contains("define"):
        start = false
        if sfile in line.sanitizePath:
          start = true
        if not ("\\" in line) and not ("/" in line) and extractFilename(sfile) in line:
          start = true
      else:
        if start:
          rdata.add(
            line.multiReplace([("_Noreturn", ""), ("(())", ""), ("WINAPI", ""),
                               ("__attribute__", ""), ("extern \"C\"", "")])
              .replace(re"\(\([_a-z]+?\)\)", "")
              .replace(re"\(\(__format__[\s]*\(__[gnu_]*printf__, [\d]+, [\d]+\)\)\);", ";")
          )
  return rdata.join("\n")

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

converter toKind*(kind: string): Kind =
  return case kind:
    of "+":
      oneOrMore
    of "*":
      zeroOrMore
    of "?":
      zeroOrOne
    else:
      exactlyOne

proc getNameKind*(name: string): tuple[name: string, kind: Kind] =
  result.name = name
  result.kind = $name[^1]

  if result.kind != exactlyOne:
    result.name = name[0 .. ^2]

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
    let kind: string = ast.children[i].kind
    result &= &"(?:{ast.children[i].name}){kind}"
  result &= "$"

proc getAstChildByName*(ast: ref Ast, name: string): ref Ast =
  for i in 0 .. ast.children.len-1:
    if name in ast.children[i].name.split("|"):
      return ast.children[i]
