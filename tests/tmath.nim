import nimterop/cimport
import unittest

type
  locale_t = object

cAddStdDir()
cImport cSearchPath("math.h")

check sin(5) == -0.9589242746631385
check abs(-5) == 5
check sqrt(4.00) == 2.0