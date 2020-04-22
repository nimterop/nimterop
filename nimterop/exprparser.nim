import strformat, strutils, macros, sets

import regex

import compiler/[ast, renderer]

import "."/treesitter/[api, c, cpp]

import "."/[globals, getters, comphelp, tshelp]

# This version of exprparser should be able to handle:
#
# All integers + integer like expressions (hex, octal, suffixes)
# All floating point expressions (except for C++'s hex floating point stuff)
# Strings and character literals, including C's escape characters (not sure if this is the same as C++'s escape characters or not)
# Math operators (+, -, /, *)
# Some Unary operators (-, !, ~). ++, --, and & are yet to be implemented
# Any identifiers
# C type descriptors (int, char, etc)
# Boolean values (true, false)
# Shift expressions (containing anything in this list)
# Cast expressions (containing anything in this list)
# Math expressions (containing anything in this list)
# Sizeof expressions (containing anything in this list)
# Cast expressions (containing anything in this list)
# Parentheses expressions (containing anything in this list)
# Expressions containing other expressions
#
# In addition to the above, it should also handle most type coercions, except
# for where Nim can't (such as uint + -int)

type
  ExprParser* = ref object
    state*: NimState
    code*: string
    name*: string

  ExprParseError* = object of CatchableError

proc newExprParser*(state: NimState, code: string, name = ""): ExprParser =
  ExprParser(state: state, code: code, name: name)

template techo(msg: varargs[string, `$`]) =
  block:
    let nimState {.inject.} = exprParser.state
    decho join(msg, "")

template val(node: TSNode): string =
  exprParser.code.getNodeVal(node)

proc mode(exprParser: ExprParser): string =
  exprParser.state.gState.mode

proc getIdent(exprParser: ExprParser, identName: string, kind = nskConst, parent = ""): PNode =
  ## Gets a cPlugin transformed identifier from `identName`
  ##
  ## Returns PNode(nkNone) if the identifier is blank
  result = newNode(nkNone)
  var ident = identName
  if ident != "_":
    # Process the identifier through cPlugin
    ident = exprParser.state.getIdentifier(ident, kind, parent)
  if kind == nskType:
    result = exprParser.state.getIdent(ident)
  elif ident.nBl and ident in exprParser.state.constIdentifiers:
    if exprParser.name.nBl:
      ident = ident & "." & exprParser.name
    result = exprParser.state.getIdent(ident)

proc getIdent(exprParser: ExprParser, node: TSNode, kind = nskConst, parent = ""): PNode =
  ## Gets a cPlugin transformed identifier from `identName`
  ##
  ## Returns PNode(nkNone) if the identifier is blank
  exprParser.getIdent(node.val, kind, parent)

proc parseChar(charStr: string): uint8 {.inline.} =
  ## Parses a character literal out of a string. This is needed
  ## because treesitter gives unescaped characters when parsing
  ## strings.
  if charStr.len == 1:
    return charStr[0].uint8

  # Handle octal, hex, unicode?
  if charStr.startsWith("\\x"):
    result = parseHexInt(charStr.replace("\\x", "0x")).uint8
  elif charStr.len == 4: # Octal
    result = parseOctInt("0o" & charStr[1 ..< charStr.len]).uint8

  if result == 0:
    case charStr
    of "\\0":
      result = ord('\0')
    of "\\a":
      result = 0x07
    of "\\b":
      result = 0x08
    of "\\e":
      result = 0x1B
    of "\\f":
      result = 0x0C
    of "\\n":
      result = '\n'.uint8
    of "\\r":
      result = 0x0D
    of "\\t":
      result = 0x09
    of "\\v":
      result = 0x0B
    of "\\\\":
      result = 0x5C
    of "\\'":
      result = '\''.uint8
    of "\\\"":
      result = '\"'.uint8
    of "\\?":
      result = 0x3F
    else:
      discard

  if result > uint8.high:
    result = uint8.high

proc getCharLit(charStr: string): PNode {.inline.} =
  ## Convert a character string into a proper Nim char lit node
  result = newNode(nkCharLit)
  result.intVal = parseChar(charStr).int64

proc getNumNode(number, suffix: string): PNode {.inline.} =
  ## Convert a C number to a Nim number PNode
  result = newNode(nkNone)
  if number.contains("."):
    let floatSuffix = number[number.len-1]
    try:
      case floatSuffix
      of 'l', 'L':
        # TODO: handle long double (128 bits)
        # result = newNode(nkFloat128Lit)
        result = newFloatNode(nkFloat64Lit, parseFloat(number[0 ..< number.len - 1]))
      of 'f', 'F':
        result = newFloatNode(nkFloat64Lit, parseFloat(number[0 ..< number.len - 1]))
      else:
        result = newFloatNode(nkFloatLit, parseFloat(number))
    except ValueError:
      raise newException(ExprParseError, &"Could not parse float value \"{number}\".")
  else:
    case suffix
    of "u", "U":
      result = newNode(nkUintLit)
    of "l", "L":
      result = newNode(nkInt32Lit)
    of "ul", "UL":
      result = newNode(nkUint32Lit)
    of "ll", "LL":
      result = newNode(nkInt64Lit)
    of "ull", "ULL":
      result = newNode(nkUint64Lit)
    else:
      result = newNode(nkIntLit)

    # I realize these regex are wasteful on performance, but
    # couldn't come up with a better idea.
    if number.contains(re"0[xX]"):
      result.intVal = parseHexInt(number)
      result.flags = {nfBase16}
    elif number.contains(re"0[bB]"):
      result.intVal = parseBinInt(number)
      result.flags = {nfBase2}
    elif number.contains(re"0[oO]"):
      result.intVal = parseOctInt(number)
      result.flags = {nfBase8}
    else:
      result.intVal = parseInt(number)

proc processNumberLiteral(exprParser: ExprParser, node: TSNode): PNode =
  ## Parse a number literal from a TSNode. Can be a float, hex, long, etc
  result = newNode(nkNone)
  let nodeVal = node.val

  var match: RegexMatch
  const reg = re"(\-)?(0\d+|0[xX][0-9a-fA-F]+|0[bB][01]+|\d+\.\d*[fFlL]?|\d*\.\d+[fFlL]?|\d+)([ulUL]*)"
  let found = nodeVal.find(reg, match)
  if found:
    let
      prefix = if match.group(0).len > 0: nodeVal[match.group(0)[0]] else: ""
      number = nodeVal[match.group(1)[0]]
      suffix = nodeVal[match.group(2)[0]]

    result = getNumNode(number, suffix)

    if result.kind != nkNone and prefix == "-":
      result = nkPrefix.newTree(
        exprParser.state.getIdent("-"),
        result
      )
  else:
    raise newException(ExprParseError, &"Could not find a number in number_literal: \"{nodeVal}\"")

proc processCharacterLiteral(exprParser: ExprParser, node: TSNode): PNode =
  let val = node.val
  result = getCharLit(val[1 ..< val.len - 1])

proc processStringLiteral(exprParser: ExprParser, node: TSNode): PNode =
  let
    nodeVal = node.val
    strVal = nodeVal[1 ..< nodeVal.len - 1]

  const
    str = "(\\\\x[[:xdigit:]]{2}|\\\\\\d{3}|\\\\0|\\\\a|\\\\b|\\\\e|\\\\f|\\\\n|\\\\r|\\\\t|\\\\v|\\\\\\\\|\\\\'|\\\\\"|[[:ascii:]])"
    reg = re(str)

  # Convert the c string escape sequences/etc to Nim chars
  var nimStr = newStringOfCap(nodeVal.len)
  for m in strVal.findAll(reg):
    nimStr.add(parseChar(strVal[m.group(0)[0]]).chr)

  result = newStrNode(nkStrLit, nimStr)

proc processTSNode(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode

proc processShiftExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = newNode(nkInfix)
  let
    left = node[0]
    right = node[1]

  let shiftSym = node.tsNodeChild(1).val.strip()

  case shiftSym
  of "<<":
    result.add exprParser.state.getIdent("shl")
  of ">>":
    result.add exprParser.state.getIdent("shr")
  else:
    raise newException(ExprParseError, &"Unsupported shift symbol \"{shiftSym}\"")

  let leftNode = exprParser.processTSNode(left, typeofNode)

  # If the typeofNode is nil, set it
  # to be the leftNode because C's type coercion
  # happens left to right, and we want to emulate it
  if typeofNode.isNil:
    typeofNode = nkCall.newTree(
      exprParser.state.getIdent("typeof"),
      leftNode
    )

  let rightNode = exprParser.processTSNode(right, typeofNode)

  result.add leftNode
  result.add nkCall.newTree(
    typeofNode,
    rightNode
  )

proc processParenthesizedExpr(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = newNode(nkPar)
  for i in 0 ..< node.len():
    result.add(exprParser.processTSNode(node[i], typeofNode))

proc processCastExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = nkCast.newTree(
    exprParser.processTSNode(node[0], typeofNode),
    exprParser.processTSNode(node[1], typeofNode)
  )

proc getNimUnarySym(csymbol: string): string =
  ## Get the Nim equivalent of a unary C symbol
  ##
  ## TODO: Add ++, --,
  case csymbol
  of "+", "-":
    result = csymbol
  of "~", "!":
    result = "not"
  else:
    raise newException(ExprParseError, &"Unsupported unary symbol \"{csymbol}\"")

proc getNimBinarySym(csymbol: string): string =
  case csymbol
  of "|", "||":
    result = "or"
  of "&", "&&":
    result = "and"
  of "^":
    result = "xor"
  of "==", "!=",
     "+", "-", "/", "*",
     ">", "<", ">=", "<=":
    result = csymbol
  of "%":
    result = "mod"
  else:
    raise newException(ExprParseError, &"Unsupported binary symbol \"{csymbol}\"")

proc processBinaryExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  # Node has left and right children ie: (2 + 7)
  result = newNode(nkInfix)

  let
    left = node[0]
    right = node[1]
    binarySym = node.tsNodeChild(1).val.strip()
    nimSym = getNimBinarySym(binarySym)

  result.add exprParser.state.getIdent(nimSym)
  let leftNode = exprParser.processTSNode(left, typeofNode)

  if typeofNode.isNil:
    typeofNode = nkCall.newTree(
      exprParser.state.getIdent("typeof"),
      leftNode
    )

  let rightNode = exprParser.processTSNode(right, typeofNode)

  result.add leftNode
  result.add nkCall.newTree(
    typeofNode,
    rightNode
  )

proc processUnaryExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = newNode(nkPar)

  let
    child = node[0]
    unarySym = node.tsNodeChild(0).val.strip()
    nimSym = getNimUnarySym(unarySym)

  if nimSym == "-":
    # Special case. The minus symbol must be in front of an integer,
    # so we have to make a gentle cast here to coerce it to one.
    # Might be bad because we are overwriting the type
    # There's probably a better way of doing this
    if typeofNode.isNil:
      typeofNode = exprParser.state.getIdent("int64")

    result.add nkPrefix.newTree(
      exprParser.state.getIdent(unarySym),
      nkPar.newTree(
        nkCall.newTree(
          exprParser.state.getIdent("int64"),
          exprParser.processTSNode(child, typeofNode)
        )
      )
    )
  else:
    result.add nkPrefix.newTree(
      exprParser.state.getIdent(nimSym),
      exprParser.processTSNode(child, typeofNode)
    )

proc processUnaryOrBinaryExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  if node.len > 1:
    # Node has left and right children ie: (2 + 7)

    # Make sure the statement is of the same type as the left
    # hand argument, since some expressions return a differing
    # type than the input types (2/3 == float)
    let binExpr = processBinaryExpression(exprParser, node, typeofNode)
    # Note that this temp var binExpr is needed for some reason, or else we get a segfault
    result = nkCall.newTree(
      typeofNode,
      binexpr
    )

  elif node.len() == 1:
    # Node has only one child, ie -(20 + 7)
    result = processUnaryExpression(exprParser, node, typeofNode)
  else:
    raise newException(ExprParseError, &"Invalid {node.getName()} \"{node.val}\"")

proc processSizeofExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = nkCall.newTree(
    exprParser.state.getIdent("sizeof"),
    exprParser.processTSNode(node[0], typeofNode)
  )

proc processTSNode(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  ## Handle all of the types of expressions here. This proc gets called recursively
  ## in the processX procs and will drill down to sub nodes.
  result = newNode(nkNone)
  let nodeName = node.getName()

  techo "NODE: ", nodeName, ", VAL: ", node.val

  case nodeName
  of "number_literal":
    # Input -> 0x1234FE, 1231, 123u, 123ul, 123ull, 1.334f
    # Output -> 0x1234FE, 1231, 123'u, 123'u32, 123'u64, 1.334
    result = exprParser.processNumberLiteral(node)
  of "string_literal":
    # Input -> "foo\0\x42"
    # Output -> "foo\0"
    result = exprParser.processStringLiteral(node)
  of "char_literal":
    # Input -> 'F', '\034' // Octal, '\x5A' // Hex, '\r' // escape sequences
    # Output ->
    result = exprParser.processCharacterLiteral(node)
  of "expression_statement", "ERROR", "translation_unit":
    # Note that we're parsing partial expressions, so the TSNode might contain
    # an ERROR node. If that's the case, they usually contain children with
    # partial results, which will contain parsed expressions
    #
    # Input (top level statement) -> ((1 + 3 - IDENT) - (int)400.0)
    # Output -> (1 + typeof(1)(3) - typeof(1)(IDENT) - typeof(1)(cast[int](400.0))) # Type casting in case some args differ
    if node.len == 1:
      result = exprParser.processTSNode(node[0], typeofNode)
    elif node.len > 1:
      result = newNode(nkStmtListExpr)
      for i in 0 ..< node.len:
        result.add exprParser.processTSNode(node[i], typeofNode)
    else:
      raise newException(ExprParseError, &"Node type \"{nodeName}\" has no children")
  of "parenthesized_expression":
    # Input -> (IDENT - OTHERIDENT)
    # Output -> (IDENT - typeof(IDENT)(OTHERIDENT)) # Type casting in case OTHERIDENT is a slightly different type (uint vs int)
    result = exprParser.processParenthesizedExpr(node, typeofNode)
  of "sizeof_expression":
    # Input -> sizeof(char)
    # Output -> sizeof(cchar)
    result = exprParser.processSizeofExpression(node, typeofNode)
  # binary_expression from the new treesitter upgrade should work here
  # once we upgrade
  of "math_expression", "logical_expression", "relational_expression",
     "bitwise_expression", "equality_expression", "binary_expression":
    # Input -> a == b, a != b, !a, ~a, a < b, a > b, a <= b, a >= b
    # Output ->
    #   typeof(a)(a == typeof(a)(b))
    #   typeof(a)(a != typeof(a)(b))
    #   (not a)
    #   (not a)
    #   typeof(a)(a < typeof(a)(b))
    #   typeof(a)(a > typeof(a)(b))
    #   typeof(a)(a <= typeof(a)(b))
    #   typeof(a)(a >= typeof(a)(b))
    result = exprParser.processUnaryOrBinaryExpression(node, typeofNode)
  of "shift_expression":
    # Input -> a >> b, a << b
    # Output -> a shr typeof(a)(b), a shl typeof(a)(b)
    result = exprParser.processShiftExpression(node, typeofNode)
  of "cast_expression":
    # Input -> (int) a
    # Output -> cast[cint](a)
    result = exprParser.processCastExpression(node, typeofNode)
  # Why are these node types named true/false?
  of "true", "false":
    # Input -> true, false
    # Output -> true, false
    result = exprParser.state.parseString(node.val)
  of "type_descriptor", "sized_type_specifier":
    # Input -> int, unsigned int, long int, etc
    # Output -> cint, cuint, clong, etc
    let ty = getType(node.val)
    if ty.len > 0:
      # If ty is not empty, one of C's builtin types has been found
      result = exprParser.getIdent(ty, nskType, parent=node.getName())
    else:
      result = exprParser.getIdent(node.val, nskType, parent=node.getName())
      if result.kind == nkNone:
        raise newException(ExprParseError, &"Missing type specifier \"{node.val}\"")
  of "identifier":
    # Input -> IDENT
    # Output -> IDENT (if found in sym table, else error)
    result = exprParser.getIdent(node, parent=node.getName())
    if result.kind == nkNone:
      raise newException(ExprParseError, &"Missing identifier \"{node.val}\"")
  else:
    raise newException(ExprParseError, &"Unsupported node type \"{nodeName}\" for node \"{node.val}\"")

  techo "NODE RESULT: ", result

proc parseCExpression*(state: NimState, code: string, name = ""): PNode =
  ## Convert the C string to a nim PNode tree
  result = newNode(nkNone)
  # This is used for keeping track of the type of the first
  # symbol used for type casting
  var tnode: PNode = nil
  let exprParser = newExprParser(state, code, name)
  try:
    withCodeAst(exprParser.code, exprParser.mode):
      result = exprParser.processTSNode(root, tnode)
  except ExprParseError as e:
    techo e.msg
    result = newNode(nkNone)
  except Exception as e:
    techo "UNEXPECTED EXCEPTION: ", e.msg
    result = newNode(nkNone)