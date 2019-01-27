import macros

type
  Symbol* = object
    name*: string
    kind*: NimSymKind

  OnSymbol* = proc(sym: var Symbol) {.cdecl.}