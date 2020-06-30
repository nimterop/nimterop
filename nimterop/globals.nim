import strutils, tables

when defined(TOAST):
  import sets, sequtils, strutils

  import "."/plugin

  import compiler/[ast, idents, modulegraphs, options]

  # import "."/treesitter/api

type
  Feature* = enum
    ast2

  State* = ref object
    # Command line arguments to toast - some forwarded from cimport.nim
    convention*: string        # `--convention | -C` to change calling convention from cdecl default
    debug*: bool               # `cDebug()` or `--debug | -d` to enable debug mode
    defines*: seq[string]      # Symbols added by `cDefine()` and `--define | -D` for C/C++ preprocessor/compiler
    dynlib*: string            # `cImport(dynlib)` or `--dynlib | -l` to specify variable containing library name
    feature*: seq[Feature]     # `--feature | -f` feature flags enabled
    includeDirs*: seq[string]  # Paths added by `cIncludeDir()` and `--includeDirs | -I` for C/C++ preprocessor/compiler
    mode*: string              # `cImport(mode)` or `--mode | -m` to override detected compiler mode - c or cpp
    nim*: string               # `--nim` to specify full path to Nim compiler
    noComments*: bool          # `--noComments | -c` to disable rendering comments in wrappers
    noHeader*: bool            # `--noHeader | -H` to skip {.header.} pragma in wrapper
    past*: bool                # `--past | -a` to print tree-sitter AST of code
    pluginSourcePath*: string  # `--pluginSourcePath` specified path to plugin file to compile and load
    pnim*: bool                # `--pnim | -n` to render Nim wrapper for header
    preprocess*: bool          # `--preprocess | -p` to enable preprocessing of code before wrapping
    prefix*: seq[string]       # `--prefix` strings to strip from start of identifiers
    recurse*: bool             # `--recurse | -r` to recurse into #include files in headers specified
    replace*: OrderedTableRef[string, string]
                               # `--replace | -G` replacement rules for identifiers
    suffix*: seq[string]       # `--suffix` strings to strip from end of identifiers
    symOverride*: seq[string]  # `cSkipSymbol()`, `cOverride()` and `--symOverride | -O` symbols to skip during wrapping
    typeMap*: TableRef[string, string]
                               # `--typeMap | -T` to map instances of type X to Y - e.g. ABC=cint

    when defined(TOAST):
      # Data fields
      code*: string              # Contents of header file currently being processed
      currentHeader*: string     # Const name of header being currently processed
      impShort*: string          # Short base name for pragma in output
      outputHandle*: File        # `--output | -o` open file handle
      sourceFile*: string        # Full path of header being currently processed

      # Plugin callbacks
      onSymbol*, onSymbolOverride*: OnSymbol
      onSymbolOverrideFinal*: OnSymbolOverrideFinal

      # Symbol tables
      constIdentifiers*: HashSet[string]     # Const names for enum casting
      identifiers*: TableRef[string, string] # Symbols that have been declared so far indexed by nimName
      skippedSyms*: HashSet[string]          # Symbols that have been skipped due to being unwrappable or
                                             # the user provided override is blank

      # Nim compiler objects
      constSection*, enumSection*, pragmaSection*, procSection*, typeSection*, varSection*: PNode
      identCache*: IdentCache
      config*: ConfigRef
      graph*: ModuleGraph

      # Table of symbols to generated AST PNode - used to implement forward declarations
      identifierNodes*: TableRef[string, PNode]

      # Used for the exprparser.nim module
      currentExpr*, currentTyCastName*: string
      # Controls whether or not the current expression
      # should validate idents against currently defined idents
      skipIdentValidation*: bool

      # Top level header for wrapper output - include imported types, pragmas and other info
      wrapperHeader*: string
    else:
      # cimport.nim specific
      compile*: seq[string]      # `cCompile()` list of files already processed
      nocache*: bool             # `cDisableCaching()` to disable caching of artifacts
      overrides*: string         # `cOverride()` code which gets added to `cPlugin()` output
      pluginSource*: string      # `cPlugin()` generated code to write to plugin file from
      searchDirs*: seq[string]   # `cSearchPath()` added directories for header search

  BuildType* = enum
    btAutoconf, btCmake

  BuildStatus* = object
    built*: bool
    buildPath*: string
    error*: string

when nimvm:
  var
    gStateCT* {.compileTime, used.} = new(State)
else:
  var
    gState*: State

when defined(TOAST):
  const
    gAtoms* {.used.} = @[
      "field_identifier",
      "identifier",
      "number_literal",
      "char_literal",
      "preproc_arg",
      "primitive_type",
      "sized_type_specifier",
      "type_identifier"
    ].toHashSet()

    gExpressions* {.used.} = @[
      "parenthesized_expression",
      "bitwise_expression",
      "shift_expression",
      "math_expression",
      "escape_sequence",
      "binary_expression",
      "unary_expression"
    ].toHashSet()

    gEnumVals* {.used.} = @[
      "identifier",
      "number_literal",
      "char_literal"
    ].concat(toSeq(gExpressions.items))

  type
    Status* = enum
      success, unknown, error

proc getCommented*(str: string): string =
  "\n# " & str.strip().replace("\n", "\n# ")

# Redirect output to file when required
template gecho*(args: string) =
  when defined(TOAST):
    when nimvm:
      echo args
    else:
      if gState.outputHandle.isNil:
        echo args
      else:
        gState.outputHandle.writeLine(args)
  else:
    echo args

template decho*(args: varargs[string, `$`]): untyped =
  let
    str = join(args, "").getCommented()
  when defined(TOAST):
    if gState.debug:
      gecho str
  else:
    if gStateCT.debug:
      echo str

template nBl*(s: typed): untyped {.used.} =
  (s.len != 0)

template Bl*(s: typed): untyped {.used.} =
  (s.len == 0)