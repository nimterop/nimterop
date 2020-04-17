import strformat, strutils, macros

import regex

import compiler/[ast, renderer]

import "."/treesitter/[api, c, cpp]

import "."/[globals, getters]

type
  ExprParser* = ref object
    state*: NimState
    code*: string

  ExprParseError* = object of CatchableError

proc newExprParser*(state: NimState, code: string): ExprParser =
  ExprParser(state: state, code: code)

template techo(msg: varargs[string, `$`]) =
  if exprParser.state.gState.debug:
    let nimState {.inject.} = exprParser.state
    necho "# " & join(msg, "").replace("\n", "\n# ")

template val*(node: TSNode): string =
  exprParser.code.getNodeVal(node)

proc mode*(exprParser: ExprParser): string =
  exprParser.state.gState.mode

template withCodeAst(exprParser: ExprParser, body: untyped): untyped =
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


proc getNumNode(number, suffix: string): PNode {.inline.} =
  result = newNode(nkNilLit)
  if number.contains("."):
    let floatSuffix = number[result.len-1]
    try:
      case floatSuffix
      of 'l', 'L':
        # TODO: handle long double (128 bits)
        # result = newNode(nkFloat128Lit)
        result = newFloatNode(nkFloat64Lit, parseFloat(number[0 ..< number.len - 1]))
      of 'f', 'F':
        result = newFloatNode(nkFloat64Lit, parseFloat(number[0 ..< number.len - 1]))
      else:
        result = newFloatNode(nkFloatLit, parseFloat(number[0 ..< number.len - 1]))
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

proc processNumberLiteral*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkNilLit)
  let nodeVal = node.val

  var match: RegexMatch
  const reg = re"(\-)?(0\d+|0[xX][0-9a-fA-F]+|0[bB][01]+|\d+\.?\d*[fFlL]?|\d*\.?\d+[fFlL]?|\d+)([ulUL]*)"
  let found = nodeVal.find(reg, match)
  if found:
    let
      prefix = if match.group(0).len > 0: nodeVal[match.group(0)[0]] else: ""
      number = nodeVal[match.group(1)[0]]
      suffix = nodeVal[match.group(2)[0]]

    result = getNumNode(number, suffix)

    if result.kind != nkNilLit and prefix == "-":
      result = nkPrefix.newTree(
        exprParser.state.getIdent("-"),
        result
      )
  else:
    raise newException(ExprParseError, &"Could not find a number in number_literal: \"{nodeVal}\"")

proc processCharacterLiteral*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkCharLit)
  result.intVal = node.val[1].int64

proc processStringLiteral*(exprParser: ExprParser, node: TSNode): PNode =
  let nodeVal = node.val
  result = newStrNode(nkStrLit, nodeVal[1 ..< nodeVal.len - 1])

proc processTSNode*(exprParser: ExprParser, node: TSNode): PNode

proc processShiftExpression*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkInfix)
  let
    left = node[0]
    right = node[1]
  var shiftSym = exprParser.code[left.tsNodeEndByte() ..< right.tsNodeStartByte()].strip()

  case shiftSym
  of "<<":
    result.add exprParser.state.getIdent("shl")
  of ">>":
    result.add exprParser.state.getIdent("shr")
  else:
    raise newException(ExprParseError, &"Unsupported shift symbol \"{shiftSym}\"")

  let
    leftNode = exprParser.processTSNode(left)
    rightNode = exprParser.processTSNode(right)

  result.add leftNode
  result.add nkCast.newTree(
    nkCall.newTree(
      exprParser.state.getIdent("typeof"),
      leftNode
    ),
    rightNode
  )

proc processParenthesizedExpr*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkPar)
  for i in 0 ..< node.len():
    result.add(exprParser.processTSNode(node[i]))

proc processLogicalExpression*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkPar)
  let child = node[0]
  var nimSym = ""

  var binarySym = exprParser.code[node.tsNodeStartByte() ..< child.tsNodeStartByte()].strip()
  techo "LOG SYM: ", binarySym

  case binarySym
  of "!":
    nimSym = "not"
  else:
    raise newException(ExprParseError, &"Unsupported logical symbol \"{binarySym}\"")

  techo "LOG CHILD: ", child.val, ", nim: ", nimSym
  result.add nkPrefix.newTree(
    exprParser.state.getIdent(nimSym),
    exprParser.processTSNode(child)
  )

proc processBitwiseExpression*(exprParser: ExprParser, node: TSNode): PNode =
  if node.len() > 1:
    result = newNode(nkInfix)
    let left = node[0]
    let right = node[1]
    var nimSym = ""

    var binarySym = exprParser.code[left.tsNodeEndByte() ..< right.tsNodeStartByte()].strip()
    techo "BIN SYM: ", binarySym

    case binarySym
    of "|", "||":
      nimSym = "or"
    of "&", "&&":
      nimSym = "and"
    of "^":
      nimSym = "xor"
    else:
      raise newException(ExprParseError, &"Unsupported binary symbol \"{binarySym}\"")

    result.add exprParser.state.getIdent(nimSym)
    let
      leftNode = exprParser.processTSNode(left)
      rightNode = exprParser.processTSNode(right)

    result.add leftNode
    result.add nkCast.newTree(
      nkCall.newTree(
        exprParser.state.getIdent("typeof"),
        leftNode
      ),
      rightNode
    )

  elif node.len() == 1:
    result = newNode(nkPar)
    let child = node[0]
    var nimSym = ""

    var binarySym = exprParser.code[node.tsNodeStartByte() ..< child.tsNodeStartByte()].strip()
    techo "BIN SYM: ", binarySym

    case binarySym
    of "~":
      nimSym = "not"
    else:
      raise newException(ExprParseError, &"Unsupported unary symbol \"{binarySym}\"")

    result.add nkPrefix.newTree(
      exprParser.state.getIdent(nimSym),
      exprParser.processTSNode(child)
    )
  else:
    raise newException(ExprParseError, &"Invalid bitwise_expression \"{node.val}\"")

proc processTSNode*(exprParser: ExprParser, node: TSNode): PNode =
  result = newNode(nkNilLit)
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
      result = exprParser.processTSNode(node[0])
    else:
      raise newException(ExprParseError, &"Node type \"{nodeName}\" has no children")

  of "parenthesized_expression":
    result = exprParser.processParenthesizedExpr(node)
  of "bitwise_expression":
    result = exprParser.processBitwiseExpression(node)
  of "shift_expression":
    result = exprParser.processShiftExpression(node)
  of "logical_expression":
    result = exprParser.processLogicalExpression(node)
  of "identifier":
    var ident = node.val
    if ident != "_":
      ident = exprParser.state.getIdentifier(ident, nskConst)
    result = exprParser.state.getIdent(ident)
  else:
    raise newException(ExprParseError, &"Unsupported node type \"{nodeName}\" for node \"{node.val}\"")

  techo "NODERES: ", result

proc codeToNode*(state: NimState, code: string): PNode =
  let exprParser = newExprParser(state, code)
  try:
    withCodeAst(exprParser):
      result = exprParser.processTSNode(root)
  except ExprParseError as e:
    techo e.msg
    result = newNode(nkNilLit)
  except Exception as e:
    techo e.msg
    result = newNode(nkNilLit)