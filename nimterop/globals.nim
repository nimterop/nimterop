type
  State* = object
    compile*, defines*, headers*, includeDirs*, searchDirs*: seq[string]

    debug*, past*, preprocess*, pretty*: bool

    consts*, procs*, types*: seq[string]

    code*, constStr*, currentHeader*, mode*, procStr*, typeStr*: string
    sourceFile*: string # eg, C or C++ source or header file
    nimout*: string # generated nim file written here, when nonempty
    keepNimout*: bool # whether to skip removing nimout (eg, for debugging)

    ## logging
    logUnhandled*: bool

var
  gStateCT* {.compiletime.}: State
  gStateRT*: State

template nBl*(s: typed): untyped =
  (s.len != 0)


type CompileMode* = enum
  c,
  cpp,

# TODO: can cligen accept enum instead of string?
const modeDefault* = $cpp # TODO: USE this everywhere relevant
