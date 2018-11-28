type
  State* = object
    compile*, defines*, headers*, includeDirs*, searchDirs*: seq[string]

    debug*, past*, preprocess*, pnim*, pretty*: bool

    consts*, procs*, types*: seq[string]

    code*, constStr*, currentHeader*, mode*, procStr*, typeStr*: string

var
  gStateCT* {.compiletime.}: State
  gStateRT*: State

template nBl*(s: untyped): untyped =
  (s.len != 0)