import nimterop/cimport
import unittest

type
  locale_t = object
  mingw_ldbl_type_t = object
  mingw_dbl_type_t = object

cDebug()
cDisableCaching()

cAddStdDir()

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars={'_'})

cImport cSearchPath("math.h")

check sin(5) == -0.9589242746631385
check abs(-5) == 5
check sqrt(4.00) == 2.0