import strformat, strutils, macros, sets, sequtils

import regex

import compiler/[ast, renderer]

import ".."/treesitter/[api, c, cpp]
import ".."/globals
import "."/[getters, comphelp, tshelp]

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
  ExprParseError* = object of CatchableError

const
  CharRegStr = "(\\\\x[[:xdigit:]]{2}|\\\\\\d{3}|\\\\0|\\\\a|\\\\b|\\\\e|\\\\f|\\\\n|\\\\r|\\\\t|\\\\v|\\\\\\\\|\\\\'|\\\\\"|[[:ascii:]])"
  CharRegex = re(CharRegStr)

template val(node: TSNode): string =
  gState.currentExpr.getNodeVal(node)

proc printDebugExpr*(gState: State, node: TSNode) =
  if gState.debug:
    gecho ("Input => " & node.val).getCommented()
    gecho gState.currentExpr.printLisp(node).getCommented()

proc getExprIdent*(gState: State, identName: string, kind = nskConst, parent = ""): PNode =
  ## Gets a cPlugin transformed identifier from `identName`
  ##
  ## Returns PNode(nkNone) if the identifier is blank
  result = newNode(nkNone)
  if gState.skipIdentValidation or identName notin gState.skippedSyms:
    var ident = identName
    if ident != "_":
      # Process the identifier through cPlugin
      ident = gState.getIdentifier(ident, kind, parent)
    if kind == nskType:
      result = gState.getIdent(ident)
    elif gState.skipIdentValidation or ident.nBl and ident in gState.constIdentifiers:
      if gState.currentTyCastName.nBl:
        ident = ident & "." & gState.currentTyCastName
      result = gState.getIdent(ident)

proc getExprIdent*(gState: State, node: TSNode, kind = nskConst, parent = ""): PNode =
  ## Gets a cPlugin transformed identifier from `identName`
  ##
  ## Returns PNode(nkNone) if the identifier is blank
  gState.getExprIdent(node.val, kind, parent)

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

proc getFloatNode(number, suffix: string): PNode {.inline.} =
  ## Get a Nim float node from a C float expression + suffix
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

proc getIntNode(number, suffix: string): PNode {.inline.} =
  ## Get a Nim int node from a C integer expression + suffix
  var
    val: BiggestInt
    flags: TNodeFlags
  if number.len > 1 and number[0] == '0':
    if number[1] in ['x', 'X']:
      val = parseHexInt(number)
      flags = {nfBase16}
    elif number[1] in ['b', 'B']:
      val = parseBinInt(number)
      flags = {nfBase2}
    else:
      val = parseOctInt(number)
      flags = {nfBase8}
  else:
    val = parseInt(number)

  case suffix
  of "u", "U":
    result = newNode(nkUintLit)
  of "l", "L":
    # If the value doesn't fit, adjust
    if val > int32.high or val < int32.low:
      result = newNode(nkInt64Lit)
    else:
      result = newNode(nkInt32Lit)
  of "ul", "UL":
    # If the value doesn't fit, adjust
    if val > uint32.high.BiggestInt:
      result = newNode(nkUInt64Lit)
    else:
      result = newNode(nkUInt32Lit)
  of "ll", "LL":
    result = newNode(nkInt64Lit)
  of "ull", "ULL":
    result = newNode(nkUint64Lit)
  else:
    result = newNode(nkIntLit)

  result.intVal = val
  result.flags = flags

proc getNumNode(number, suffix: string): PNode {.inline.} =
  ## Convert a C number to a Nim number PNode
  if number.contains("."):
    getFloatNode(number, suffix)
  else:
    getIntNode(number, suffix)

proc processNumberLiteral(gState: State, node: TSNode): PNode =
  ## Parse a number literal from a TSNode. Can be a float, hex, long, etc
  result = newNode(nkNone)
  let nodeVal = node.val
  var
    prefix: string
    number = nodeVal
    suffix: string

  const
    singleEndings = ["u", "l", "U", "L"]
    doubleEndings = ["ul", "UL", "ll", "LL"]
    tripleEndings = ["ull", "ULL"]

  if number.startsWith("-"):
    number = number[1 ..< number.len]
    prefix = "-"
  if tripleEndings.any(proc (s: string): bool = number.endsWith(s)):
    suffix = number[^3 .. ^1]
    number = number[0 ..< ^3]
  elif doubleEndings.any(proc (s: string): bool = number.endsWith(s)):
    suffix = number[^2 .. ^1]
    number = number[0 ..< ^2]
  elif singleEndings.any(proc (s: string): bool = number.endsWith(s)):
    suffix = $number[number.len - 1]
    number = number[0 ..< ^1]

  result = getNumNode(number, suffix)

  if result.kind != nkNone and prefix == "-":
    result = nkPrefix.newTree(
      gState.getIdent("-"),
      result
    )

proc processCharacterLiteral(gState: State, node: TSNode): PNode =
  # Input => 'G'
  #
  # (char_literal 1 1 3 "'G'")
  #
  # Output => 'G'
  #
  # nkCharLit("G")
  let val = node.val
  result = getCharLit(val[1 ..< val.len - 1])

proc processStringLiteral(gState: State, node: TSNode): PNode =
  # Input => "\n\rfoobar\0\'"
  #
  # (string_literal 1 1 16 ""\n\rfoobar\0\'""
  #  (escape_sequence 1 2 2 "\n")
  #  (escape_sequence 1 4 2 "\r")
  #  (escape_sequence 1 12 2 "\0")
  #  (escape_sequence 1 14 2 "\'")
  # )
  #
  # Output => "\n\cfoobar\x00\'"
  #
  # nkStrLit("\x0A\x0Dfoobar\x00\'")
  let
    nodeVal = node.val
    strVal = nodeVal[1 ..< nodeVal.len - 1]

  # Convert the c string escape sequences/etc to Nim chars
  var nimStr = newStringOfCap(nodeVal.len)
  for m in strVal.findAll(CharRegex):
    nimStr.add(parseChar(strVal[m.group(0)[0]]).chr)

  result = newStrNode(nkStrLit, nimStr)

proc processTSNode(gState: State, node: TSNode, typeofNode: var PNode): PNode

proc processParenthesizedExpr(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  # Input => (a + b)
  #
  # (parenthesized_expression 1 1 7
  #  (math_expression 1 2 5
  #   (identifier 1 2 1 "a")
  #   (identifier 1 6 1 "b")
  #  )
  # )
  #
  # Output => (typeof(a)(a + typeof(a)(b)))
  #
  # nkPar(
  #  nkCall(
  #   nkCall(
  #    nkIdent("typeof"),
  #    nkIdent("a")
  #   ),
  #   nkInfix(
  #    nkIdent("+"),
  #    nkIdent("a"),
  #    nkCall(
  #     nkCall(
  #      nkIdent("typeof"),
  #      nkIdent("a")
  #     ),
  #     nkIdent("b")
  #    )
  #   )
  #  )
  # )
  result = newNode(nkPar)
  for i in 0 ..< node.len():
    result.add(gState.processTSNode(node[i], typeofNode))

proc processCastExpression(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  # Input => (int)a
  #
  # (cast_expression 1 1 6 "(int)a"
  #  (type_descriptor 1 2 3 "int"
  #   (primitive_type 1 2 3 "int")
  #  )
  #  (identifier 1 6 1 "a")
  # )
  #
  # Output => cast[cint](a)
  #
  # nkCast(
  #  nkIdent("cint"),
  #  nkIdent("a")
  # )
  result = nkCast.newTree(
    gState.processTSNode(node[0], typeofNode),
    gState.processTSNode(node[1], typeofNode)
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
  of "<<":
    result = "shl"
  of ">>":
    result = "shr"
  else:
    raise newException(ExprParseError, &"Unsupported binary symbol \"{csymbol}\"")

proc processBinaryExpression(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  # Node has left and right children ie: (2 + 7)
  #
  # Input => a == b
  #
  # (equality_expression 1 1 6
  #  (identifier 1 1 1 "a")
  #  (identifier 1 6 1 "b")
  # )
  #
  # Output => a == typeof(a)(b)
  #
  # nkInfix(
  #  nkIdent("=="),
  #  nkIdent("a"),
  #  nkCall(
  #   nkCall(
  #    nkIdent("typeof"),
  #    nkIdent("a")
  #   ),
  #   nkIdent("b")
  #  )
  # )
  result = newNode(nkInfix)

  let
    left = node[0]
    right = node[1]
    binarySym = node.tsNodeChild(1).val.strip()
    nimSym = getNimBinarySym(binarySym)

  result.add gState.getIdent(nimSym)
  let leftNode = gState.processTSNode(left, typeofNode)

  if typeofNode.isNil:
    typeofNode = nkCall.newTree(
      gState.getIdent("typeof"),
      leftNode
    )

  let rightNode = gState.processTSNode(right, typeofNode)

  result.add leftNode
  result.add nkCall.newTree(
    typeofNode,
    rightNode
  )
  if binarySym == "/":
    # Special case. Nim's operators generally output
    # the same type they take in, except for division.
    # So we need to emulate C here and cast the whole
    # expression to the type of the first arg
    result = nkCall.newTree(
      typeofNode,
      result
    )

proc processUnaryExpression(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  # Input => !a
  #
  # (logical_expression 1 1 2 "!a"
  #  (identifier 1 2 1 "a")
  # )
  #
  # Output => (not a)
  #
  # nkPar(
  #  nkPrefix(
  #   nkIdent("not"),
  #   nkIdent("a")
  #  )
  # )
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
      typeofNode = gState.getIdent("int64")

    result.add nkPrefix.newTree(
      gState.getIdent(unarySym),
      nkPar.newTree(
        nkCall.newTree(
          gState.getIdent("int64"),
          gState.processTSNode(child, typeofNode)
        )
      )
    )
  else:
    result.add nkPrefix.newTree(
      gState.getIdent(nimSym),
      gState.processTSNode(child, typeofNode)
    )

proc processUnaryOrBinaryExpression(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  ## Processes both unary (-1, ~true, !something) and binary (a + b, c * d) expressions
  if node.len > 1:
    # Node has left and right children ie: (2 + 7)
    result = processBinaryExpression(gState, node, typeofNode)
  elif node.len() == 1:
    # Node has only one child, ie -(20 + 7)
    result = processUnaryExpression(gState, node, typeofNode)
  else:
    raise newException(ExprParseError, &"Invalid {node.getName()} \"{node.val}\"")

proc processSizeofExpression(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  # Input => sizeof(int)
  #
  # (sizeof_expression 1 1 11 "sizeof(int)"
  #  (type_descriptor 1 8 3 "int"
  #   (primitive_type 1 8 3 "int")
  #  )
  # )
  #
  # Output => sizeof(cint)
  #
  # nkCall(
  #  nkIdent("sizeof"),
  #  nkIdent("cint")
  # )
  result = nkCall.newTree(
    gState.getIdent("sizeof"),
    gState.processTSNode(node[0], typeofNode)
  )

proc processTSNode(gState: State, node: TSNode, typeofNode: var PNode): PNode =
  ## Handle all of the types of expressions here. This proc gets called recursively
  ## in the processX procs and will drill down to sub nodes.
  result = newNode(nkNone)
  let nodeName = node.getName()

  decho "NODE: ", nodeName, ", VAL: ", node.val

  case nodeName
  of "number_literal":
    # Input -> 0x1234FE, 1231, 123u, 123ul, 123ull, 1.334f
    # Output -> 0x1234FE, 1231, 123'u, 123'u32, 123'u64, 1.334
    result = gState.processNumberLiteral(node)
  of "string_literal":
    # Input -> "foo\0\x42"
    # Output -> "foo\0"
    result = gState.processStringLiteral(node)
  of "char_literal":
    # Input -> 'F', '\060' // Octal, '\x5A' // Hex, '\r' // escape sequences
    # Output -> 'F', '0', 'Z', '\r'
    result = gState.processCharacterLiteral(node)
  of "expression_statement", "ERROR", "translation_unit":
    # Note that we're parsing partial expressions, so the TSNode might contain
    # an ERROR node. If that's the case, they usually contain children with
    # partial results, which will contain parsed expressions
    #
    # Input (top level statement) -> ((1 + 3 - IDENT) - (int)400.0)
    # Output -> (1 + typeof(1)(3) - typeof(1)(IDENT) - typeof(1)(cast[int](400.0))) # Type casting in case some args differ
    if node.len == 1:
      result = gState.processTSNode(node[0], typeofNode)
    elif node.len > 1:
      var nodes: seq[PNode]
      for i in 0 ..< node.len:
        let subNode = gState.processTSNode(node[i], typeofNode)
        if subNode.kind != nkNone:
          nodes.add(subNode)
          # Multiple nodes can get tricky. Don't support them yet, unless they
          # have at most one valid node
          if nodes.len > 1:
            raise newException(ExprParseError, &"Node type \"{nodeName}\" with val ({node.val}) has more than one non empty node")
      if nodes.len == 1:
        result = nodes[0]
    else:
      raise newException(ExprParseError, &"Node type \"{nodeName}\" has no children")
  of "parenthesized_expression":
    # Input -> (IDENT - OTHERIDENT)
    # Output -> (IDENT - typeof(IDENT)(OTHERIDENT)) # Type casting in case OTHERIDENT is a slightly different type (uint vs int)
    result = gState.processParenthesizedExpr(node, typeofNode)
  of "sizeof_expression":
    # Input -> sizeof(char)
    # Output -> sizeof(cchar)
    result = gState.processSizeofExpression(node, typeofNode)
  # binary_expression from the new treesitter upgrade should work here
  # once we upgrade
  of "math_expression", "logical_expression", "relational_expression",
     "bitwise_expression", "equality_expression", "binary_expression",
     "shift_expression":
    # Input -> a == b, a != b, !a, ~a, a < b, a > b, a <= b, a >= b, a >> b, a << b
    # Output ->
    #   typeof(a)(a == typeof(a)(b))
    #   typeof(a)(a != typeof(a)(b))
    #   (not a)
    #   (not a)
    #   typeof(a)(a < typeof(a)(b))
    #   typeof(a)(a > typeof(a)(b))
    #   typeof(a)(a <= typeof(a)(b))
    #   typeof(a)(a >= typeof(a)(b))
    #   a shr typeof(a)(b)
    #   a shl typeof(a)(b)
    result = gState.processUnaryOrBinaryExpression(node, typeofNode)
  of "cast_expression":
    # Input -> (int) a
    # Output -> cast[cint](a)
    result = gState.processCastExpression(node, typeofNode)
  # Why are these node types named true/false?
  of "true", "false":
    # Input -> true, false
    # Output -> true, false
    result = gState.parseString(node.val)
  of "type_descriptor":
    # Input => int*
    # (type_descriptor 1 2 4 "int*"
    #  (type_identifier 1 2 3 "int")
    #  (abstract_pointer_declarator 1 3 1 "*")
    # )
    #
    # Output => ptr int
    #
    # nkPtrTy(
    #  nkIdent("int")
    # )
    let pointerDecl = node.anyChildInTree("abstract_pointer_declarator")

    if pointerDecl.isNil:
      result = gState.processTSNode(node[0], typeofNode)
    else:
      let pointerCount = pointerDecl.getXCount("abstract_pointer_declarator")
      result = gState.newPtrTree(pointerCount, gState.processTSNode(node[0], typeofNode))
  of "sized_type_specifier", "primitive_type", "type_identifier":
    # Input -> int, unsigned int, long int, etc
    # Output -> cint, cuint, clong, etc
    let ty = getType(node.val)
    if ty.len > 0:
      # If ty is not empty, one of C's builtin types has been found
      result = gState.getExprIdent(ty, nskType, parent=node.getName())
    else:
      result = gState.getExprIdent(node.val, nskType, parent=node.getName())
    if result.kind == nkNone:
      raise newException(ExprParseError, &"Missing type specifier \"{node.val}\"")
  of "identifier":
    # Input -> IDENT
    # Output -> IDENT (if found in sym table, else error)
    result = gState.getExprIdent(node, parent=node.getName())
    if result.kind == nkNone:
      raise newException(ExprParseError, &"Missing identifier \"{node.val}\"")
  of "comment":
    discard
  else:
    raise newException(ExprParseError, &"Unsupported node type \"{nodeName}\" for node \"{node.val}\"")

  if result.kind != nkNone:
    decho "NODE RESULT: ", result

proc parseCExpression*(gState: State, codeRoot: TSNode): PNode =
  ## Parse a c expression from a root ts node

  # This var is used for keeping track of the type of the first
  # symbol used for type casting
  var tnode: PNode = nil
  result = newNode(nkNone)
  try:
    result = gState.processTSNode(codeRoot, tnode)
  except ExprParseError as e:
    decho e.msg
    result = newNode(nkNone)
  except Exception as e:
    decho "UNEXPECTED EXCEPTION: ", e.msg
    result = newNode(nkNone)

proc parseCExpression*(gState: State, code: string, name = "", skipIdentValidation = false): PNode =
  ## Convert the C string to a nim PNode tree
  gState.currentExpr = code
  gState.currentTyCastName = name
  gState.skipIdentValidation = skipIdentValidation

  withCodeAst(gState.currentExpr, gState.mode):
    result = gState.parseCExpression(root)

  # Clear the state
  gState.currentExpr = ""
  gState.currentTyCastName = ""
  gState.skipIdentValidation = false