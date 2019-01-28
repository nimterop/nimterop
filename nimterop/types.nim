#[
note:
this should pull as few dependencies as needed by the wrapper, one option is, for the types that carry a dependency, wrap the type declaration inside something like:
```
when defined(nimteropNeeds_va_list):
  type
    va_list* {.importc, header:"<stdarg.h>".} = object
```

note:
nimterop should replace the generated wrappers with the nim-idiomatic version, eg:
```
proc mylib(a: ptrdiff_t) => proc mylib(a: ByteAddress)
```

note:
as needed, provide (platform specific) nim aliases which can be used eg to compute sizeof, eg:
type foo_t* {.importc, header: "<foo.h>".} = distinct int32
]#

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
