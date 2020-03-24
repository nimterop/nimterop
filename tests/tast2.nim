import tables

import nimterop/[cimport]

static:
  cDebug()

cOverride:
  const
    A* = 2

  type
    A1* = A0

cImport("include/tast2.h", flags="-d -f:ast2 -ENK_")

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

assert A == 2
assert B == 1.0
assert C == 0x10
assert D == "hello"
assert E == 'c'

assert A0 is object
testFields(A0, {"f1": "cint"}.toTable())
assert A1 is A0
testFields(A1, {"f1": "cint"}.toTable())
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

assert A9p is array[3, cstring]
#assert A9 is array[4, cchar]
assert A10 is array[3, array[6, cstring]]
assert A11 is ptr array[3, cstring]
assert A111 is array[12, ptr A1]

assert A12 is proc(a1: cint, b: cint, c: ptr cint, a4: ptr cint, count: array[4, ptr cint], `func`: proc(a1: cint, a2: cint): cint): ptr ptr cint
assert A13 is proc(a1: cint, a2: cint, `func`: proc()): cint

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

assert U1 is object
assert sizeof(U1) == sizeof(cfloat)

assert U2 is object
assert sizeof(U2) == 256 * sizeof(cint)

assert PANEL_WINDOW == 1
assert PANEL_GROUP == 2
assert PANEL_POPUP == 4
assert PANEL_CONTEXTUAL == 16
assert PANEL_COMBO == 32
assert PANEL_MENU == 64
assert PANEL_TOOLTIP == 128
assert PANEL_SET_NONBLOCK == 240
assert PANEL_SET_POPUP == 244
assert PANEL_SET_SUB == 246

assert cmGray == 1000000
assert pfGray16 == 1000011
assert pfYUV422P8 == pfYUV420P8 + 1
assert pfRGB27 == cmRGB.VSPresetFormat + 11
assert pfCompatYUY2 == pfCompatBGR32 + 1