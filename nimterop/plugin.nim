import macros, sets, tables

type
  Symbol* = object
    name*: string
    parent*: string
    kind*: NimSymKind
    override*: string
  StringHash = HashSet[string]
  OnSymbol* = proc(sym: var Symbol) {.cdecl.}
  OnSymbolOverrideFinal* = proc(typ: string): StringHash {.cdecl.}

var
  cOverrides*: Table[string, StringHash]

cOverrides = initTable[string, StringHash]()
cOverrides["nskType"] = StringHash()
cOverrides["nskConst"] = StringHash()
cOverrides["nskProc"] = StringHash()

proc onSymbolOverrideFinal*(typ: string): StringHash {.exportc, dynlib.} =
  result = cOverrides[typ]
