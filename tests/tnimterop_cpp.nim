import nimterop/cimport
import unittest

cDebug()

cIncludeDir "$projpath/include"
cAddSearchDir "$projpath/include"
cCompile  cSearchPath "test2.cpp"
# TODO: allow this to have correct language: cImport("test2.h")
cImport cSearchPath "test2.hpp"

check TEST_INT == 512
check test_call_int() == 5

var foo: Foo
check foo.bar == 2

# var foo2: Foo2[int]
# var foo2: Foo2Int

when false:
  doAssert TEST_FLOAT == 5.12
  doAssert TEST_HEX == 0x512

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
      
  doAssert test_call_int_param(5).field1 == 5
  doAssert test_call_int_param2(5, s2).field1 == 11
  doAssert test_call_int_param3(5, s).field1 == 10
  doAssert test_call_int_param4(e) == e2
