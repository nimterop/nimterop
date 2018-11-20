import macros

type
  Ast* = object
    sym*: string
    start*, stop*: int
    parent*: ptr Ast
    children*: seq[Ast]

var
  gDefines* {.compiletime.}: seq[string]
  gCompile* {.compiletime.}: seq[string]
  gConsts* {.compiletime.}: seq[string]
  gHeaders* {.compiletime.}: seq[string]
  gIncludeDirs* {.compiletime.}: seq[string]
  gProcs* {.compiletime.}: seq[string]
  gTypes* {.compiletime.}: seq[string]

  gCode* {.compiletime.}: string
  gConstStr* {.compiletime.}: string
  gCurrentHeader* {.compiletime.}: string
  gDebug* {.compiletime.}: bool
  gReorder* {.compiletime.}: bool
  gProcStr* {.compiletime.}: string
  gTypeStr* {.compiletime.}: string

template nBl*(s: untyped): untyped =
  (s.len() != 0)