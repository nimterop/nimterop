import sequtils, sets, tables, strutils

import regex

import "."/plugin

when not declared(CIMPORT):
  import compiler/[ast, idents, modulegraphs, options]

  import "."/treesitter/api

const
  gAtoms {.used.} = @[
    "field_identifier",
    "identifier",
    "number_literal",
    "char_literal",
    "preproc_arg",
    "primitive_type",
    "sized_type_specifier",
    "type_identifier"
  ].toHashSet()

  gExpressions {.used.} = @[
    "parenthesized_expression",
    "bitwise_expression",
    "shift_expression",
    "math_expression",
    "escape_sequence"
  ].toHashSet()

  gEnumVals {.used.} = @[
    "identifier",
    "number_literal",
    "char_literal"
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
      tonim*: proc (ast: ref Ast, node: TSNode, gState: State)
    regex*: Regex

  AstTable {.used.} = TableRef[string, seq[ref Ast]]

  State = ref object
    compile*, defines*, headers*, includeDirs*, searchDirs*, prefix*, suffix*, symOverride*: seq[string]

    debug*, includeHeader*, nocache*, nocomments*, past*, preprocess*, pnim*, recurse*: bool

    code*, convention*, dynlib*, mode*, nim*, overrides*, pluginSource*, pluginSourcePath*: string

    replace*: OrderedTableRef[string, string]

    feature*: seq[Feature]

    onSymbol*, onSymbolOverride*: OnSymbol
    onSymbolOverrideFinal*: OnSymbolOverrideFinal

    outputHandle*: File

    # All symbols that have been declared so far indexed by nimName
    identifiers*: TableRef[string, string]

    # All const names for enum casting
    constIdentifiers*: HashSet[string]

    # All symbols that have been skipped due to
    # being unwrappable or the user provided
    # override is blank
    skippedSyms*: HashSet[string]

    # Legacy ast fields, remove when ast2 becomes default
    constStr*, enumStr*, procStr*, typeStr*: string

    commentStr*, debugStr*, skipStr*: string

    # Nim compiler objects
    when not declared(CIMPORT):
      constSection*, enumSection*, pragmaSection*, procSection*, typeSection*, varSection*: PNode
      identCache*: IdentCache
      config*: ConfigRef
      graph*: ModuleGraph

      # Craeted symbols to generated AST - forward declaration tracking
      identifierNodes*: TableRef[string, PNode]

    currentHeader*, impShort*, sourceFile*: string

    # Used for the exprparser.nim module
    currentExpr*, currentTyCastName*: string

    data*: seq[tuple[name, val: string]]

    nodeBranch*: seq[string]

  Feature* = enum
    ast2

var
  gStateCT {.compiletime, used.} = new(State)

template nBl(s: typed): untyped {.used.} =
  (s.len != 0)

template Bl(s: typed): untyped {.used.} =
  (s.len == 0)

when not declared(CIMPORT):
  export gAtoms, gExpressions, gEnumVals, Kind, Ast, AstTable, State, nBl, Bl

  # Redirect output to file when required
  template gecho*(args: string) =
    if gState.outputHandle.isNil:
      echo args
    else:
      gState.outputHandle.writeLine(args)

  template decho*(args: varargs[string, `$`]): untyped =
    if gState.debug:
      gecho join(args, "").getCommented()