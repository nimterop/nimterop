# see https://github.com/nimterop/nimterop/issues/79

when (NimMajor, NimMinor, NimPatch) < (0, 19, 9):
  # clean this up once upgraded; adapted from std/time_t
  when defined(nimdoc):
    type
      impl = distinct int64
      Time = impl
  elif defined(windows):
    when defined(i386) and defined(gcc):
      type Time {.importc: "time_t", header: "<time.h>".} = distinct int32
    else:
      type Time {.importc: "time_t", header: "<time.h>".} = distinct int64
  elif defined(posix):
    import posix
  type
    time_t* = Time
    time64_t* = Time
    wchar_t* {.importc.} = object
else:
  import std/time_t as time_t_temp
  type
    time_t* = time_t_temp.Time
    time64_t* = time_t_temp.Time

  when defined(c) or defined(nimdoc):
    # http://www.cplusplus.com/reference/cwchar/wchar_t/
    # In C++, wchar_t is a distinct fundamental type (and thus it is
    # not defined in <cwchar> nor any other header).
    type
      wchar_t* {.importc, header:"<cwchar>".} = object
  elif defined(cpp):
    type
      wchar_t* {.importc.} = object

type
  ptrdiff_t* = ByteAddress

type
  va_list* {.importc, header:"<stdarg.h>".} = object

template enumOp*(op, typ, typout) =
  proc op*(x: typ, y: int): typout {.borrow.}
  proc op*(x: int, y: typ): typout {.borrow.}
  proc op*(x, y: typ): typout {.borrow.}

template defineEnum*(typ) =
  type
    typ* = distinct int

  enumOp(`+`,   typ, typ)
  enumOp(`-`,   typ, typ)
  enumOp(`*`,   typ, typ)
  enumOp(`<`,   typ, bool)
  enumOp(`<=`,  typ, bool)
  enumOp(`==`,  typ, bool)
  enumOp(`div`, typ, typ)
  enumOp(`mod`, typ, typ)

  proc `shl`*(x: typ, y: int): typ {.borrow.}
  proc `shl`*(x: int, y: typ): typ {.borrow.}
  proc `shl`*(x, y: typ): typ {.borrow.}

  proc `shr`*(x: typ, y: int): typ {.borrow.}
  proc `shr`*(x: int, y: typ): typ {.borrow.}
  proc `shr`*(x, y: typ): typ {.borrow.}

  proc `or`*(x: typ, y: int): typ {.borrow.}
  proc `or`*(x: int, y: typ): typ {.borrow.}
  proc `or`*(x, y: typ): typ {.borrow.}

  proc `and`*(x: typ, y: int): typ {.borrow.}
  proc `and`*(x: int, y: typ): typ {.borrow.}
  proc `and`*(x, y: typ): typ {.borrow.}

  proc `xor`*(x: typ, y: int): typ {.borrow.}
  proc `xor`*(x: int, y: typ): typ {.borrow.}
  proc `xor`*(x, y: typ): typ {.borrow.}

  proc `/`(x, y: typ): typ =
    return (x.float / y.float).int.typ
  proc `/`*(x: typ, y: int): typ = `/`(x, y.typ)
  proc `/`*(x: int, y: typ): typ = `/`(x.typ, y)

  proc `$` *(x: typ): string {.borrow.}
