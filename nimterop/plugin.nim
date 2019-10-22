import macros, sets, tables

type
  Symbol* = object
    name*: string
    parent*: string
    kind*: NimSymKind
    override*: string

  OnSymbol* = proc(sym: var Symbol) {.cdecl.}
  OnSymbolOverrideFinal* = proc(typ: string): HashSet[string] {.cdecl.}

var
  cOverrides*: Table[string, HashSet[string]]

cOverrides = initTable[string, HashSet[string]]()
cOverrides["nskType"] = initSet[string]()
cOverrides["nskConst"] = initSet[string]()
cOverrides["nskProc"] = initSet[string]()

proc onSymbolOverrideFinal*(typ: string): HashSet[string] {.exportc, dynlib.} =
  result = cOverrides[typ]
