import macros, strutils

import compiler/[ast, idents, lineinfos, msgs, options, parser, pathutils, renderer]

import ".."/[globals, treesitter/api]
import "."/[getters, tshelp]

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

proc printTree*(gState: State, pnode: PNode, offset = ""): string =
  if not pnode.isNil and gState.debug and pnode.kind != nkNone:
    result &= "\n# " & offset & $pnode.kind & "("
    case pnode.kind
    of nkCharLit:
      result &= ($pnode.intVal.char).escape & ")"
    of nkIntLit..nkUInt64Lit:
      result &= $pnode.intVal & ")"
    of nkFloatLit..nkFloat128Lit:
      result &= $pnode.floatVal & ")"
    of nkStrLit..nkTripleStrLit:
      result &= pnode.strVal.escape & ")"
    of nkSym:
      result &= $pnode.sym & ")"
    of nkIdent:
      result &= "\"" & $pnode.ident.s & "\")"
    else:
      if pnode.sons.len != 0:
        for i in 0 ..< pnode.sons.len:
          result &= gState.printTree(pnode.sons[i], offset & " ")
          if i != pnode.sons.len - 1:
            result &= ","
        result &= "\n# " & offset & ")"
      else:
        result &= ")"
    if offset.len == 0:
      result &= "\n"

proc printDebug*(gState: State, pnode: PNode) =
  if gState.debug and pnode.kind != nkNone:
    gecho ("Output => " & $pnode).getCommented()
    gecho gState.printTree(pnode)

proc getDefaultLineInfo*(gState: State): TLineInfo =
  result = newLineInfo(gState.config, gState.sourceFile.AbsoluteFile, 0, 0)

proc getLineInfo*(gState: State, node: TSNode): TLineInfo =
  # Get Nim equivalent line:col info from node
  let
    (line, col) = gState.getLineCol(node)

  result = newLineInfo(gState.config, gState.sourceFile.AbsoluteFile, line, col)

proc getIdent*(gState: State, name: string, info: TLineInfo, exported = true): PNode =
  if name.nBl:
    # Get ident PNode for name + info
    let
      exp = getIdent(gState.identCache, "*")
      ident = getIdent(gState.identCache, name)

    if exported:
      result = newNode(nkPostfix)
      result.add newIdentNode(exp, info)
      result.add newIdentNode(ident, info)
    else:
      result = newIdentNode(ident, info)

proc getIdent*(gState: State, name: string): PNode =
  gState.getIdent(name, gState.getDefaultLineInfo(), exported = false)

proc getIdentName*(node: PNode): string =
  if not node.isNil:
    for i in 0 ..< node.len:
      if node[i].kind == nkIdent and $node[i] != "*":
        result = $node[i]
    if result.Bl and node.len > 0:
      result = node[0].getIdentName()

proc getNameInfo*(gState: State, node: TSNode, kind: NimSymKind, parent = ""):
  tuple[name, origname: string, info: TLineInfo] =
  # Shortcut to get identifier name and info (node value and line:col)
  result.origname = gState.getNodeVal(node)
  result.name = gState.getIdentifier(result.origname, kind, parent)
  if result.name.nBl:
    if kind == nskType:
      result.name = result.name.getType()
    result.info = gState.getLineInfo(node)

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