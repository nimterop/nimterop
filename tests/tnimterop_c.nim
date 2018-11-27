import nimterop/cimport

cDebug()

cDefine("FORCE")
cIncludeDir "$projpath/include"
cAddSearchDir "$projpath/include"
cCompile cSearchPath("test.c")
cImport cSearchPath "test.h"

doAssert TEST_INT == 512
doAssert TEST_FLOAT == 5.12
doAssert TEST_HEX == 0x512

var
  pt: PRIMTYPE
  ct: CUSTTYPE

  s: STRUCT1
  s2: STRUCT2
  s3: STRUCT3
  s4: STRUCT4

  e: ENUM
  e2: ENUM2 = enum5

  vptr: VOIDPTR
  iptr: INTPTR

pt = 3
ct = 4

s.field1 = 5
s2.field1 = 6
s3.field1 = 7

e = enum1
e2 = enum4

doAssert test_call_int() == 5
doAssert test_call_int_param(5).field1 == 5
doAssert test_call_int_param2(5, s2).field1 == 11
doAssert test_call_int_param3(5, s).field1 == 10
doAssert test_call_int_param4(e) == e2

cAddStdDir()
