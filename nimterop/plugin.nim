import macros

type
  Symbol* = object
    name*: string
    parent*: string
    kind*: NimSymKind
    override*: string

  OnSymbol* = proc(sym: var Symbol) {.cdecl.}
