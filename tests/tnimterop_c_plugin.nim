import strutils

proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
  if sym.name == "_Kernel":
    sym.name = "uKernel"
  else:
    sym.name = sym.name.strip(chars={'_'})