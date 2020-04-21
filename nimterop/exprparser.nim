import strformat, strutils, macros, sets

import regex

import compiler/[ast, renderer]

import "."/treesitter/[api, c, cpp]

import "."/[globals, getters, utils]

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
  if exprParser.state.gState.debug:
    let nimState {.inject.} = exprParser.state
    necho join(msg, "").getCommented

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
  if exprParser.name.nBl and ident in exprParser.state.constIdentifiers:
    ident = ident & "." & exprParser.name
  if ident != "":
    result = exprParser.state.getIdent(ident)

proc getIdent(exprParser: ExprParser, node: TSNode, kind = nskConst, parent = ""): PNode =
  ## Gets a cPlugin transformed identifier from `identName`
  ##
  ## Returns PNode(nkNone) if the identifier is blank
  exprParser.getIdent(node.val, kind, parent)

template withCodeAst(exprParser: ExprParser, body: untyped): untyped =
  ## A simple template to inject the TSNode into a body of code
  var parser = tsParserNew()
  defer:
    parser.tsParserDelete()

  doAssert exprParser.code.nBl, "Empty code"
  if exprParser.mode == "c":
    doAssert parser.tsParserSetLanguage(treeSitterC()), "Failed to load C parser"
  elif exprParser.mode == "cpp":
    doAssert parser.tsParserSetLanguage(treeSitterCpp()), "Failed to load C++ parser"
  else:
    doAssert false, &"Invalid parser {exprParser.mode}"

  var
    tree = parser.tsParserParseString(nil, exprParser.code.cstring, exprParser.code.len.uint32)
    root {.inject.} = tree.tsTreeRootNode()

  body

  defer:
    tree.tsTreeDelete()

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
      return
    except ValueError:
      raise newException(ExprParseError, &"Could not parse float value \"{number}\".")

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

proc processLogicalExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  result = newNode(nkPar)
  let child = node[0]
  var nimSym = ""

  let binarySym = node.tsNodeChild(0).val.strip()
  techo "LOG SYM: ", binarySym

  case binarySym
  of "!":
    nimSym = "not"
  else:
    raise newException(ExprParseError, &"Unsupported logical symbol \"{binarySym}\"")

  techo "LOG CHILD: ", child.val, ", nim: ", nimSym
  result.add nkPrefix.newTree(
    exprParser.state.getIdent(nimSym),
    exprParser.processTSNode(child, typeofNode)
  )

proc processMathExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  if node.len > 1:
    # Node has left and right children ie: (2 + 7)
    var
      res = newNode(nkInfix)
    let
      left = node[0]
      right = node[1]

    let mathSym = node.tsNodeChild(1).val.strip()
    techo "MATH SYM: ", mathSym

    res.add exprParser.state.getIdent(mathSym)
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

    res.add leftNode
    res.add nkCall.newTree(
      typeofNode,
      rightNode
    )

    # Make sure the statement is of the same type as the left
    # hand argument, since some expressions return a differing
    # type than the input types (2/3 == float)
    result = nkCall.newTree(
      typeofNode,
      res
    )

  elif node.len() == 1:
    # Node has only one child, ie -(20 + 7)
    result = newNode(nkPar)
    let child = node[0]
    var nimSym = ""

    let unarySym = node.tsNodeChild(0).val.strip()
    techo "MATH SYM: ", unarySym

    case unarySym
    of "+":
      nimSym = "+"
    of "-":
      # Special case. The minus symbol must be in front of an integer,
      # so we have to make a gental cast here to coerce it to one.
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
      return
    else:
      raise newException(ExprParseError, &"Unsupported unary symbol \"{unarySym}\"")

    result.add nkPrefix.newTree(
      exprParser.state.getIdent(nimSym),
      exprParser.processTSNode(child, typeofNode)
    )
  else:
    raise newException(ExprParseError, &"Invalid bitwise_expression \"{node.val}\"")

proc processBitwiseExpression(exprParser: ExprParser, node: TSNode, typeofNode: var PNode): PNode =
  if node.len() > 1:
    result = newNode(nkInfix)

    let
      left = node[0]
      right = node[1]

    var nimSym = ""

    let binarySym = node.tsNodeChild(1).val.strip()
    techo "BIN SYM: ", binarySym

    case binarySym
    of "|", "||":
      nimSym = "or"
    of "&", "&&":
      nimSym = "and"
    of "^":
      nimSym = "xor"
    of "==", "!=":
      nimSym = binarySym
    else:
      raise newException(ExprParseError, &"Unsupported binary symbol \"{binarySym}\"")

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

  elif node.len() == 1:
    result = newNode(nkPar)
    let child = node[0]
    var nimSym = ""

    let unarySym = node.tsNodeChild(0).val.strip()
    techo "BIN SYM: ", unarySym

    # TODO: Support more symbols here. ++, --, &
    case unarySym
    of "~":
      nimSym = "not"
    else:
      raise newException(ExprParseError, &"Unsupported unary symbol \"{unarySym}\"")

    result.add nkPrefix.newTree(
      exprParser.state.getIdent(nimSym),
      exprParser.processTSNode(child, typeofNode)
    )
  else:
    raise newException(ExprParseError, &"Invalid bitwise_expression \"{node.val}\"")

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
    result = exprParser.processNumberLiteral(node)
  of "string_literal":
    result = exprParser.processStringLiteral(node)
  of "char_literal":
    result = exprParser.processCharacterLiteral(node)
  of "expression_statement", "ERROR", "translation_unit":
    # This may be wrong. What can be in an expression?
    if node.len > 0:
      result = exprParser.processTSNode(node[0], typeofNode)
    else:
      raise newException(ExprParseError, &"Node type \"{nodeName}\" has no children")
  of "parenthesized_expression":
    result = exprParser.processParenthesizedExpr(node, typeofNode)
  of "sizeof_expression":
    result = exprParser.processSizeofExpression(node, typeofNode)
  # binary_expression from the new treesitter upgrade should work here
  # once we upgrade
  of "bitwise_expression", "equality_expression", "binary_expression":
    result = exprParser.processBitwiseExpression(node, typeofNode)
  of "math_expression":
    result = exprParser.processMathExpression(node, typeofNode)
  of "shift_expression":
    result = exprParser.processShiftExpression(node, typeofNode)
  of "cast_expression":
    result = exprParser.processCastExpression(node, typeofNode)
  of "logical_expression":
    result = exprParser.processLogicalExpression(node, typeofNode)
  # Why are these node types named true/false?
  of "true", "false":
    result = exprParser.state.parseString(node.val)
  of "type_descriptor", "sized_type_specifier":
    let ty = getType(node.val)
    result = exprParser.getIdent(ty, nskType, parent=node.getName())
    if result.kind == nkNone:
      result = exprParser.state.getIdent(ty)
  of "identifier":
    result = exprParser.getIdent(node, parent=node.getName())
    if result.kind == nkNone:
      raise newException(ExprParseError, &"Could not get identifier \"{node.val}\"")
  else:
    raise newException(ExprParseError, &"Unsupported node type \"{nodeName}\" for node \"{node.val}\"")

  techo "NODE RESULT: ", result

proc parseCExpression*(state: NimState, code: string, name = ""): PNode =
  ## Convert the C string to a nim PNode tree
  result = newNode(nkNone)
  # This is used for keeping track of the type of the first
  # symbol
  var tnode: PNode = nil
  let exprParser = newExprParser(state, code, name)
  try:
    withCodeAst(exprParser):
      result = exprParser.processTSNode(root, tnode)
  except ExprParseError as e:
    techo e.msg
    result = newNode(nkNone)
  except Exception as e:
    techo "UNEXPECTED EXCEPTION: ", e.msg
    result = newNode(nkNone)
