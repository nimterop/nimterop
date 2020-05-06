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

proc getPtrType*(str: string): string =
  result = case str:
    of "cchar":
      "cstring"
    of "object":
      "pointer"
    of "FILE":
      "File"
    else:
      str

proc newPtrTree*(gState: State, count: int, typ: PNode): PNode =
  # Create nkPtrTy tree depending on count
  #
  # Reduce by 1 if Nim type available for ptr X - e.g. ptr cchar = cstring
  result = typ
  var
    count = count
  if typ.kind == nkIdent:
    let
      tname = typ.ident.s
      ptname = getPtrType(tname)
    if tname != ptname:
      # If Nim type available, use that ident
      result = gState.getIdent(ptname, typ.info, exported = false)
      # One ptr reduced
      count -= 1
  if count > 0:
    # Nested nkPtrTy(typ) depending on count
    #
    # [ptr ...] typ
    #
    # nkPtrTy(
    #  nkPtrTy(
    #    typ
    #  )
    # )
    var
      nresult = newNode(nkPtrTy)
      parent = nresult
      child: PNode
    for i in 1 ..< count:
      child = newNode(nkPtrTy)
      parent.add child
      parent = child
    parent.add result
    result = nresult