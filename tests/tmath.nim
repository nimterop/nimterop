import unittest
import nimterop/cimport

cOverride:
  type
    locale_t = object
    mingw_ldbl_type_t = object
    mingw_dbl_type_t = object

when defined(windows):
  cOverride:
    type
      complex = object

static:
  when (NimMajor, NimMinor, NimPatch) < (1, 0, 0):
    cSkipSymbol @["mingw_choose_expr", "EXCEPTION_DEFINED", "COMPLEX_DEFINED", "matherr", "HUGE", "FP_ILOGB0", "FP_ILOGBNAN"]
  else:
    cSkipSymbol @["mingw_choose_expr", "EXCEPTION_DEFINED", "COMPLEX_DEFINED", "matherr", "HUGE"]
  cDebug()
  cDisableCaching()
  cAddStdDir()

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars={'_'}).replace("__", "_")

const FLAGS {.strdefine.} = ""
cImport(cSearchPath("math.h"), flags = FLAGS)

check sin(5) == -0.9589242746631385
check abs(-5) == 5
check sqrt(4.00) == 2.0
