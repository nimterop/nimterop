import tables

import nimterop/[cimport]

static:
  cDebug()

cImport("include/tast2.h", flags="-d -f:ast2")

proc testFields(t: typedesc, fields: Table[string, string] = initTable[string, string]()) =
  var
    obj: t
    count = 0
  for name, value in obj.fieldPairs():
    count += 1
    assert name in fields, $t & "." & name & " invalid"
    assert $fields[name] == $typeof(value),
      "typeof(" & $t & ":" & name & ") != " & fields[name] & ", is " & $typeof(value)
  assert count == fields.len, "Failed for " & $t

assert A == 1
assert B == 1.0
assert C == 0x10
assert D == "hello"
assert E == 'c'

assert A0 is object
testFields(A0)
assert A1 is object
testFields(A1)
assert A2 is object
testFields(A2)
assert A3 is object
testFields(A3)
assert A4 is object
testFields(A4)
assert A4p is ptr A4
assert A5 is cint
assert A6 is ptr cint
assert A7 is ptr ptr A0
assert A8 is pointer

assert A9 is array[3, cstring]
assert A10 is array[3, array[6, cstring]]
assert A11 is ptr array[3, cstring]

assert A12 is proc(a1: cint, b: cint, c: ptr cint, a4: ptr cint, count: array[4, ptr cint], `func`: proc(a1: cint, a2: cint): cint): ptr ptr cint
assert A13 is proc(a1: cint, a2: cint): cint

assert A14 is object
testFields(A14, {"a1": "cchar"}.toTable())

assert A15 is object
testFields(A15, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())

assert A16 is object
testFields(A16, {"f1": "cchar"}.toTable())

assert A17 is object
testFields(A17, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())
assert A18 is A17
assert A18p is ptr A17

assert A19 is object
testFields(A19, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())
assert A19p is ptr A19

assert A20 is object
testFields(A20, {"a1": "cchar"}.toTable())
assert A21 is A20
assert A21p is ptr A20

assert A22 is object
testFields(A22, {"f1": "ptr ptr cint", "f2": "array[0..254, ptr cint]"}.toTable())