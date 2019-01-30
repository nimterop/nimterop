# see https://github.com/genotrance/nimterop/issues/79

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
  type time_t* = Time
else:
  import std/time_t as time_t_temp
  type time_t* = time_t_temp.Time

type
  ptrdiff_t* = ByteAddress

type
  va_list* {.importc, header:"<stdarg.h>".} = object

when defined(c):
  # http://www.cplusplus.com/reference/cwchar/wchar_t/ In C++, wchar_t is a distinct fundamental type (and thus it is not defined in <cwchar> nor any other header).
  type
    wchar_t* {.importc, header:"<cwchar>".} = object
elif defined(cpp):
  type
    wchar_t* {.importc.} = object

template defineEnum*(typ: untyped) =
  type
    typ* = distinct int

  proc `+`*(x: typ, y: int): typ {.borrow.}
  proc `+`*(x: int, y: typ): typ {.borrow.}
  proc `+`*(x, y: typ): typ {.borrow.}

  proc `-`*(x: typ, y: int): typ {.borrow.}
  proc `-`*(x: int, y: typ): typ {.borrow.}
  proc `-`*(x, y: typ): typ {.borrow.}

  proc `*`*(x: typ, y: int): typ {.borrow.}
  proc `*`*(x: int, y: typ): typ {.borrow.}
  proc `*`*(x, y: typ): typ {.borrow.}

  proc `<`*(x: typ, y: int): bool {.borrow.}
  proc `<`*(x: int, y: typ): bool {.borrow.}
  proc `<`*(x, y: typ): bool {.borrow.}

  proc `<=`*(x: typ, y: int): bool {.borrow.}
  proc `<=`*(x: int, y: typ): bool {.borrow.}
  proc `<=`*(x, y: typ): bool {.borrow.}

  proc `==`*(x: typ, y: int): bool {.borrow.}
  proc `==`*(x: int, y: typ): bool {.borrow.}
  proc `==`*(x, y: typ): bool {.borrow.}

  proc `shl`*(x: typ, y: int): typ {.borrow.}
  proc `shl`*(x: int, y: typ): typ {.borrow.}
  proc `shl`*(x, y: typ): typ {.borrow.}

  proc `shr`*(x: typ, y: int): typ {.borrow.}
  proc `shr`*(x: int, y: typ): typ {.borrow.}
  proc `shr`*(x, y: typ): typ {.borrow.}

  proc `div`*(x: typ, y: int): typ {.borrow.}
  proc `div`*(x: int, y: typ): typ {.borrow.}
  proc `div`*(x, y: typ): typ {.borrow.}

  proc `mod`*(x: typ, y: int): typ {.borrow.}
  proc `mod`*(x: int, y: typ): typ {.borrow.}
  proc `mod`*(x, y: typ): typ {.borrow.}


  proc `$` *(x: typ): string {.borrow.}