import compiler/[ast, lineinfos, msgs, options, parser, renderer]

import "."/[globals, getters]

proc handleError*(conf: ConfigRef, info: TLineInfo, msg: TMsgKind, arg: string) =
  # Raise exception in parseString() instead of exiting for errors
  if msg < warnMin:
    raise newException(Exception, msgKindToString(msg))

proc parseString*(gState: State, str: string): PNode =
  # Parse a string into Nim AST - use custom error handler that raises
  # an exception rather than exiting on failure
  try:
    result = parseString(
      str, gState.identCache, gState.config, errorHandler = handleError
    )
  except:
    decho getCurrentExceptionMsg()