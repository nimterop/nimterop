#[
design goals
* speed of compilation (implies: not too many heavy deps)
]#

type Symbol* = ref object
  name*: string # input symbol
  #[
  TODO:
  provide other context as input, eg `NimNodeKind`
  ]#

type Result* = object
  skip*: bool ## whether to skip symbol
  name2*: string ## new name given
  #[
  TODO:
  provide behavior when ambiguous symbol is given
  ]#

{.push importc.}
proc onSymbol*(result: var Result, symbol: Symbol)
{.pop.}
