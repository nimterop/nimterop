import tables

import regex

import treesitter/runtime

type
  Kind* = enum
    exactlyOne
    oneOrMore     # +
    zeroOrMore    # *
    zeroOrOne     # ?

  Ast* = object
    name*: string
    kind*: Kind
    children*: seq[ref Ast]
    tonim*: proc (ast: ref Ast, node: TSNode)
    regex*: Regex

  State* = object
    compile*, defines*, headers*, includeDirs*, searchDirs*: seq[string]

    debug*, past*, preprocess*, pnim*, pretty*, recurse*: bool

    consts*, enums*, procs*, types*: seq[string]

    code*, constStr*, currentHeader*, enumStr*, mode*, procStr*, typeStr*: string
    sourceFile*: string # eg, C or C++ source or header file

    ast*: Table[string, seq[ref Ast]]
    data*: seq[tuple[name, val: string]]
    grammar*: seq[tuple[grammar: string, call: proc(ast: ref Ast, node: TSNode) {.nimcall.}]]

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
