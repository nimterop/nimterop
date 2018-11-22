import macros

type
  Sym* = enum
    ERROR, IGNORED,
    enumerator, enumerator_list, enum_specifier,
    declaration,
    field_declaration, field_declaration_list, field_identifier, function_declarator,
    identifier,
    number_literal,
    parameter_declaration, parameter_list, pointer_declarator, preproc_arg, preproc_def, primitive_type,
    struct_specifier,
    type_definition, type_identifier

  Ast* = object
    sym*: Sym
    start*, stop*: uint32
    parent*: ref Ast
    children*: seq[ref Ast]

var
  gDefines* {.compiletime.}: seq[string]
  gCompile* {.compiletime.}: seq[string]
  gConsts* {.compiletime.}: seq[string]
  gHeaders* {.compiletime.}: seq[string]
  gIncludeDirs* {.compiletime.}: seq[string]
  gProcs* {.compiletime.}: seq[string]
  gSearchDirs* {.compiletime.}: seq[string]
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