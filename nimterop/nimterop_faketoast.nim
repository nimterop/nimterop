#[

]#

import dynlib, strutils, macros
import "."/nimteropfuns

## generic utils that shd be moved somewhere else
macro declName(a: typed): untyped =
  let a2 = getImpl(a)
  newLit $a2[0]

template loadSymbol(pluginExe: string, symbol: typed): untyped =
  let funName = declName(symbol)
  cast[type(symbol)](handle.symAddr(funName))

## nimterop utils
proc main(pluginExe: string) =
  let handle = loadLib(pluginExe)
  doAssert handle != nil

  let onSymbol2 = loadSymbol(pluginExe, onSymbol)
  doAssert onSymbol2 != nil, pluginExe

  proc onSymbol(symbol: Symbol): Result = onSymbol2(result, symbol)

  for name in "foo _foo fooBar".split:
    let symbol = Symbol(name: name)
    let ret = onSymbol(symbol)
    echo ret

when isMainModule:
  import cligen
  dispatch(main)
