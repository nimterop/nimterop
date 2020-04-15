# see https://github.com/nimterop/nimterop/issues/79

import std/time_t as time_t_temp
type
  time_t* = time_t_temp.Time
  time64_t* = time_t_temp.Time

when defined(cpp):
  # http://www.cplusplus.com/reference/cwchar/wchar_t/
  # In C++, wchar_t is a distinct fundamental type (and thus it is
  # not defined in <cwchar> nor any other header).
  type
    wchar_t* {.importc.} = object
else:
  type
    wchar_t* {.importc, header:"<cwchar>".} = object

type
  ptrdiff_t* = ByteAddress

type
  va_list* {.importc, header:"<stdarg.h>".} = object

template enumOp*(op, typ, typout) =
  proc op*(x: typ, y: cint): typout {.borrow.}
  proc op*(x: cint, y: typ): typout {.borrow.}
  proc op*(x, y: typ): typout {.borrow.}

  proc op*(x: typ, y: int): typout = op(x, y.cint)
  proc op*(x: int, y: typ): typout = op(x.cint, y)

template defineEnum*(typ) =
  # Create a `distinct cint` type for C enums since Nim enums
  # need to be in order and cannot have duplicates.
  type
    typ* = distinct cint

  # Enum operations allowed
  enumOp(`+`,   typ, typ)
  enumOp(`-`,   typ, typ)
  enumOp(`*`,   typ, typ)
  enumOp(`<`,   typ, bool)
  enumOp(`<=`,  typ, bool)
  enumOp(`==`,  typ, bool)
  enumOp(`div`, typ, typ)
  enumOp(`mod`, typ, typ)

  # These don't work with `enumOp()` for some reason
  proc `shl`*(x: typ, y: cint): typ {.borrow.}
  proc `shl`*(x: cint, y: typ): typ {.borrow.}
  proc `shl`*(x, y: typ): typ {.borrow.}

  proc `shr`*(x: typ, y: cint): typ {.borrow.}
  proc `shr`*(x: cint, y: typ): typ {.borrow.}
  proc `shr`*(x, y: typ): typ {.borrow.}

  proc `or`*(x: typ, y: cint): typ {.borrow.}
  proc `or`*(x: cint, y: typ): typ {.borrow.}
  proc `or`*(x, y: typ): typ {.borrow.}

  proc `and`*(x: typ, y: cint): typ {.borrow.}
  proc `and`*(x: cint, y: typ): typ {.borrow.}
  proc `and`*(x, y: typ): typ {.borrow.}

  proc `xor`*(x: typ, y: cint): typ {.borrow.}
  proc `xor`*(x: cint, y: typ): typ {.borrow.}
  proc `xor`*(x, y: typ): typ {.borrow.}

  proc `/`*(x, y: typ): typ =
    return (x.float / y.float).cint.typ
  proc `/`*(x: typ, y: cint): typ = `/`(x, y.typ)
  proc `/`*(x: cint, y: typ): typ = `/`(x.typ, y)

  proc `$`*(x: typ): string {.borrow.}
