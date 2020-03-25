import macros, sets, tables

import nimterop/[cimport]

static:
  cDebug()

cOverride:
  const
    A* = 2

  type
    A1* = A0

when defined(HEADER):
  cDefine("HEADER")
  const
    flags = " -H"
    imp = @["importc", "header:headertast2"]
else:
  const
    flags = ""
    imp = @[]

cImport("include/tast2.h", flags="-d -f:ast2 -ENK_" & flags)

proc getPragmas(n: NimNode): HashSet[string] =
  for i in 0 ..< n.len:
    if n[i].kind == nnkPragma:
      for j in 0 ..< n[i].len:
        if n[i][j].kind == nnkIdent:
          result.incl $n[i][j]
        elif n[i][j].kind == nnkExprColonExpr:
          result.incl $n[i][j][0] & ":" & $n[i][j][1]
    else:
      result.incl n[i].getPragmas()

macro checkPragmas(t: typed, pragmas: static[seq[string]]): untyped =
  let
    ast = t.getImpl()
    prag = ast.getPragmas()
    exprag = pragmas.toHashSet()
  doAssert symmetricDifference(prag, exprag).len == 0,
    "\nWrong number of pragmas in " & $t & "\n" & $prag & " vs " & $exprag

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

const
  pragmas = @["bycopy"] & imp

assert A0 is object
testFields(A0, {"f1": "cint"}.toTable())
checkPragmas(A0, pragmas)

assert A1 is A0
testFields(A1, {"f1": "cint"}.toTable())

assert A2 is object
testFields(A2)
checkPragmas(A2, pragmas)

assert A3 is object
testFields(A3)
checkPragmas(A3, pragmas)

assert A4 is object
testFields(A4)
checkPragmas(A4, pragmas)

assert A4p is ptr A4
checkPragmas(A4p, imp)

assert A5 is cint
checkPragmas(A5, imp)

assert A6 is ptr cint
checkPragmas(A6, imp)

assert A7 is ptr ptr A0
checkPragmas(A7, imp)

assert A8 is pointer
checkPragmas(A8, imp)

assert A9p is array[3, cstring]
checkPragmas(A9p, imp)

#assert A9 is array[4, cchar]
#checkPragmas(A9, imp)

assert A10 is array[3, array[6, cstring]]
checkPragmas(A10, imp)

assert A11 is ptr array[3, cstring]
checkPragmas(A11, imp)

assert A111 is array[12, ptr A1]
checkPragmas(A111, imp)

assert A12 is proc(a1: cint, b: cint, c: ptr cint, a4: ptr cint, count: array[4, ptr cint], `func`: proc(a1: cint, a2: cint): cint): ptr ptr cint
checkPragmas(A12, imp)

assert A13 is proc(a1: cint, a2: cint, `func`: proc()): cint
checkPragmas(A13, imp)

assert A14 is object
testFields(A14, {"a1": "cchar"}.toTable())
checkPragmas(A14, pragmas)

assert A15 is object
testFields(A15, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())
checkPragmas(A15, pragmas)

assert A16 is object
testFields(A16, {"f1": "cchar"}.toTable())
checkPragmas(A16, pragmas)

assert A17 is object
testFields(A17, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())
checkPragmas(A17, pragmas)

assert A18 is A17
checkPragmas(A18, imp)

assert A18p is ptr A17
checkPragmas(A18p, imp)

assert A19 is object
testFields(A19, {"a1": "cstring", "a2": "array[0..0, ptr cint]"}.toTable())
checkPragmas(A19, pragmas)

assert A19p is ptr A19
checkPragmas(A19p, imp)

assert A20 is object
testFields(A20, {"a1": "cchar"}.toTable())
checkPragmas(A20, pragmas)

assert A21 is A20
checkPragmas(A21, imp)

assert A21p is ptr A20
checkPragmas(A21p, imp)

assert A22 is object
testFields(A22, {"f1": "ptr ptr cint", "f2": "array[0..254, ptr cint]"}.toTable())
checkPragmas(A22, pragmas)

assert U1 is object
assert sizeof(U1) == sizeof(cfloat)
checkPragmas(U1, pragmas & @["union"])

assert U2 is object
assert sizeof(U2) == 256 * sizeof(cint)
checkPragmas(U2, pragmas & @["union"])

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