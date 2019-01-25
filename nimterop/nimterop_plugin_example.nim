import "."/nimteropfuns
import strutils

proc onSymbol(result: var Result, symbol: Symbol, dummy: int) {.exportc.} =
  if symbol.name.startsWith "_":
    result.name2 = "c_" & symbol.name
  else:
    result.name2 = symbol.name
