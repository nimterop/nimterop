import nimterop/cimport
import macros

cDebug()

cIncludeDir("include")
cCompile("test.c")
cImport("test.h")

assert TEST_INT == 512
assert TEST_FLOAT == 5.12
assert TEST_HEX == 0x512

var
  pt: PRIMTYPE
  ct: CUSTTYPE

  s: STRUCT1
  s2: STRUCT2
  s3: STRUCT3

  e: ENUM
  e2: ENUM2 = enum5

pt = 3
ct = 4

s.field1 = 5
s2.field1 = 6
s3.field1 = 7

e = enum1
e2 = enum4
    
assert test_call_int() == 5
assert test_call_int_param(5).field1 == 5
assert test_call_int_param2(5, s2).field1 == 11
assert test_call_int_param3(5, s).field1 == 10
assert test_call_int_param4(e) == e2