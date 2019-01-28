#[
TODO:
this should pull as few dependencies as needed by the wrapper, one option is, for the types that carry a dependency, wrap the type declaration inside something like:
```
when defined(nimteropNeeds_va_list):
  type
    va_list* {.importc, header:"<stdarg.h>".} = object
```

TODO:
nimterop should replace the generated wrappers with the nim-idiomatic version, eg:
```
proc mylib(a: ptrdiff_t) => proc mylib(a: ByteAddress)
```
]#

from std/time_t import nil # for time_t

export time_t

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
