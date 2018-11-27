import macros, ospaths, strformat, strutils

import regex

import git, globals

proc sanitizePath*(path: string): string =
  path.multiReplace([("\\\\", $DirSep), ("\\", $DirSep), ("//", $DirSep)])

proc getIdentifier*(str: string): string =
  result = str.strip(chars={'_'})

proc getType*(str: string): string =
  result = str.strip(chars={'_'}).replace(re"([u]?int[\d]+)_t", "$1").replace(re"^void$", "object")

proc getLit*(str: string): string =
  if str.contains(re"^[\-]?[\d]+$") or
    str.contains(re"^[\-]?[\d]*\.[\d]+$") or
    str.contains(re"^0x[\d]+$"):
    return str

proc getNodeValIf*(node: ref Ast, esym: Sym): string =
  if esym != node.sym:
    return

  return gCode[node.start .. node.stop-1].strip()

proc getLineCol*(node: ref Ast): tuple[line, col: int] =
  result.line = 1
  result.col = 1
  for i in 0 .. node.start-1:
    if gCode[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1

proc getGccPaths*(mode = "c"): string =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode

  return staticExec("gcc -Wp,-v -x" & mmode & " " & nul)

proc getPreprocessor*(fullpath: string, mode = "cpp"): string =
  var
    mmode = if mode == "cpp": "c++" else: mode
    cmd = &"gcc -E -dD -x{mmode} "
    gdef, gdir: seq[string]

    rdata: seq[string] = @[]
    start = false
    sfile = fullpath.sanitizePath

  when nimvm:
    gdef = gDefines
    gdir = gIncludeDirs
  else:
    gdef = gDefinesRT
    gdir = gIncludeDirsRT

  for inc in gdir:
    cmd &= &"-I\"{inc}\" "

  for def in gdef:
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
