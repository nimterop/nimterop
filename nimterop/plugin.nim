import macros

type
  Symbol* = object
    name*: string
    parent*: string
    kind*: NimSymKind

  OnSymbol* = proc(sym: var Symbol) {.cdecl.}