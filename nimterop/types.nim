type
  time_t* = int32
  ptrdiff_t* = ByteAddress
  va_list* {.importc: "va_list", header:"<stdarg.h>".} = object