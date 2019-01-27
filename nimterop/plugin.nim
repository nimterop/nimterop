import macros

type
  Symbol* = object
    name*: string
    kind*: NimSymKind

  onSymbolType* = proc(sym: var Symbol) {.cdecl.}