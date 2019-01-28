import sequtils, sets, tables

import regex

import "."/plugin

when not declared(CIMPORT):
  import "."/treesitter/runtime

const
  gAtoms {.used.} = @[
    "field_identifier",
    "identifier",
    "number_literal",
    "preproc_arg",
    "primitive_type",
    "sized_type_specifier",
    "type_identifier"
  ].toSet()

  gExpressions {.used.} = @[
    "parenthesized_expression",
    "bitwise_expression",
    "shift_expression",
    "math_expression"
  ].toSet()

  gEnumVals {.used.} = @[
    "identifier",
    "number_literal"
  ].concat(toSeq(gExpressions.items))

type
  Kind = enum
    exactlyOne
    oneOrMore     # +
    zeroOrMore    # *
    zeroOrOne     # ?
    orWithNext    # !

  Ast = object
    name*: string
    kind*: Kind
    recursive*: bool
    children*: seq[ref Ast]
    when not declared(CIMPORT):
      tonim*: proc (ast: ref Ast, node: TSNode, nimState: NimState)
    regex*: Regex

  AstTable {.used.} = TableRef[string, seq[ref Ast]]

  State = object
    compile*, defines*, headers*, includeDirs*, searchDirs*, symOverride*: seq[string]

    nocache*, debug*, past*, preprocess*, pnim*, pretty*, recurse*: bool

    code*, mode*, pluginSourcePath*, sourceFile*: string

    onSymbol*: OnSymbol

  NimState {.used.} = ref object
    identifiers*: TableRef[string, string]

    constStr*, debugStr*, enumStr*, procStr*, typeStr*: string

    currentHeader*: string

    data*: seq[tuple[name, val: string]]

var
  gStateCT {.compiletime, used.}: State
  gStateRT {.used.}: State

template nBl(s: typed): untyped {.used.} =
  (s.len != 0)

type CompileMode = enum
  c,
  cpp,

# TODO: can cligen accept enum instead of string?
const modeDefault {.used.} = $cpp # TODO: USE this everywhere relevant

when not declared(CIMPORT):
  export gAtoms, gExpressions, gEnumVals, Kind, Ast, AstTable, State, NimState, gStateRT, nBl, CompileMode, modeDefault