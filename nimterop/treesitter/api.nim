{.experimental: "codeReordering".}

import strutils, os

import ".."/[setup, paths, types]

static:
  treesitterSetup()

const sourcePath = incDir() / "treesitter" / "lib"

when defined(Linux):
  {.passC: "-std=c11".}

{.passC: "-DUTF8PROC_STATIC".}
{.passC: "-I$1" % (sourcePath / "include").}
{.passC: "-I$1" % (sourcePath / "src").}
{.passC: "-I$1" % (sourcePath / ".." / ".." / "utf8proc").}

{.compile: sourcePath / "src" / "lib.c".}

### Generated below

{.hint[ConvFromXtoItselfNotNeeded]: off.}

defineEnum(TSInputEncoding)
defineEnum(TSSymbolType)
defineEnum(TSLogType)
const
  headerapi {.used.} = sourcePath / "include" / "tree_sitter" / "api.h"
  TREE_SITTER_LANGUAGE_VERSION* = 9
  TSInputEncodingUTF8* = 0.TSInputEncoding
  TSInputEncodingUTF16* = 1.TSInputEncoding
  TSSymbolTypeRegular* = 0.TSSymbolType
  TSSymbolTypeAnonymous* = 1.TSSymbolType
  TSSymbolTypeAuxiliary* = 2.TSSymbolType
  TSLogTypeParse* = 0.TSLogType
  TSLogTypeLex* = 1.TSLogType
type
  TSSymbol* = uint16
  TSLanguage* = object
  TSParser* = object
  TSTree* = object
  TSPoint* {.importc, header: headerapi, bycopy.} = object
    row*: uint32
    column*: uint32

  TSRange* {.importc, header: headerapi, bycopy.} = object
    start_point*: TSPoint
    end_point*: TSPoint
    start_byte*: uint32
    end_byte*: uint32

  TSInput* {.importc, header: headerapi, bycopy.} = object
    payload*: pointer
    read*: proc (payload: pointer; byte_index: uint32; position: TSPoint;
               bytes_read: ptr uint32): cstring {.nimcall.}
    encoding*: TSInputEncoding

  TSLogger* {.importc, header: headerapi, bycopy.} = object
    payload*: pointer
    log*: proc (payload: pointer; a1: TSLogType; a2: cstring) {.nimcall.}

  TSInputEdit* {.importc, header: headerapi, bycopy.} = object
    start_byte*: uint32
    old_end_byte*: uint32
    new_end_byte*: uint32
    start_point*: TSPoint
    old_end_point*: TSPoint
    new_end_point*: TSPoint

  TSNode* {.importc, header: headerapi, bycopy.} = object
    context*: array[4, uint32]
    id*: pointer
    tree*: ptr TSTree

  TSTreeCursor* {.importc, header: headerapi, bycopy.} = object
    tree*: pointer
    id*: pointer
    context*: array[2, uint32]

proc ts_parser_new*(): ptr TSParser {.importc, header: headerapi.}
proc ts_parser_delete*(a1: ptr TSParser) {.importc, header: headerapi.}
proc ts_parser_language*(a1: ptr TSParser): ptr TSLanguage {.importc, header: headerapi.}
proc ts_parser_set_language*(a1: ptr TSParser; a2: ptr TSLanguage): bool {.importc,
    header: headerapi.}
proc ts_parser_logger*(a1: ptr TSParser): TSLogger {.importc, header: headerapi.}
proc ts_parser_set_logger*(a1: ptr TSParser; a2: TSLogger) {.importc, header: headerapi.}
proc ts_parser_print_dot_graphs*(a1: ptr TSParser; a2: cint) {.importc,
    header: headerapi.}
proc ts_parser_halt_on_error*(a1: ptr TSParser; a2: bool) {.importc, header: headerapi.}
proc ts_parser_parse*(a1: ptr TSParser; a2: ptr TSTree; a3: TSInput): ptr TSTree {.importc,
    header: headerapi.}
proc ts_parser_parse_string*(a1: ptr TSParser; a2: ptr TSTree; a3: cstring; a4: uint32): ptr TSTree {.
    importc, header: headerapi.}
proc ts_parser_parse_string_encoding*(a1: ptr TSParser; a2: ptr TSTree; a3: cstring;
                                     a4: uint32; a5: TSInputEncoding): ptr TSTree {.
    importc, header: headerapi.}
proc ts_parser_enabled*(a1: ptr TSParser): bool {.importc, header: headerapi.}
proc ts_parser_set_enabled*(a1: ptr TSParser; a2: bool) {.importc, header: headerapi.}
proc ts_parser_operation_limit*(a1: ptr TSParser): cuint {.importc, header: headerapi.}
proc ts_parser_set_operation_limit*(a1: ptr TSParser; a2: cuint) {.importc,
    header: headerapi.}
proc ts_parser_reset*(a1: ptr TSParser) {.importc, header: headerapi.}
proc ts_parser_set_included_ranges*(a1: ptr TSParser; a2: ptr TSRange; a3: uint32) {.
    importc, header: headerapi.}
proc ts_parser_included_ranges*(a1: ptr TSParser; a2: ptr uint32): ptr TSRange {.importc,
    header: headerapi.}
proc ts_tree_copy*(a1: ptr TSTree): ptr TSTree {.importc, header: headerapi.}
proc ts_tree_delete*(a1: ptr TSTree) {.importc, header: headerapi.}
proc ts_tree_root_node*(a1: ptr TSTree): TSNode {.importc, header: headerapi.}
proc ts_tree_edit*(a1: ptr TSTree; a2: ptr TSInputEdit) {.importc, header: headerapi.}
proc ts_tree_get_changed_ranges*(a1: ptr TSTree; a2: ptr TSTree; a3: ptr uint32): ptr TSRange {.
    importc, header: headerapi.}
proc ts_tree_print_dot_graph*(a1: ptr TSTree; a2: ptr FILE) {.importc, header: headerapi.}
proc ts_tree_language*(a1: ptr TSTree): ptr TSLanguage {.importc, header: headerapi.}
proc ts_node_start_byte*(a1: TSNode): uint32 {.importc, header: headerapi.}
proc ts_node_start_point*(a1: TSNode): TSPoint {.importc, header: headerapi.}
proc ts_node_end_byte*(a1: TSNode): uint32 {.importc, header: headerapi.}
proc ts_node_end_point*(a1: TSNode): TSPoint {.importc, header: headerapi.}
proc ts_node_symbol*(a1: TSNode): TSSymbol {.importc, header: headerapi.}
proc ts_node_type*(a1: TSNode): cstring {.importc, header: headerapi.}
proc ts_node_string*(a1: TSNode): cstring {.importc, header: headerapi.}
proc ts_node_eq*(a1: TSNode; a2: TSNode): bool {.importc, header: headerapi.}
proc ts_node_is_null*(a1: TSNode): bool {.importc, header: headerapi.}
proc ts_node_is_named*(a1: TSNode): bool {.importc, header: headerapi.}
proc ts_node_is_missing*(a1: TSNode): bool {.importc, header: headerapi.}
proc ts_node_has_changes*(a1: TSNode): bool {.importc, header: headerapi.}
proc ts_node_has_error*(a1: TSNode): bool {.importc, header: headerapi.}
proc ts_node_parent*(a1: TSNode): TSNode {.importc, header: headerapi.}
proc ts_node_child*(a1: TSNode; a2: uint32): TSNode {.importc, header: headerapi.}
proc ts_node_named_child*(a1: TSNode; a2: uint32): TSNode {.importc, header: headerapi.}
proc ts_node_child_count*(a1: TSNode): uint32 {.importc, header: headerapi.}
proc ts_node_named_child_count*(a1: TSNode): uint32 {.importc, header: headerapi.}
proc ts_node_next_sibling*(a1: TSNode): TSNode {.importc, header: headerapi.}
proc ts_node_next_named_sibling*(a1: TSNode): TSNode {.importc, header: headerapi.}
proc ts_node_prev_sibling*(a1: TSNode): TSNode {.importc, header: headerapi.}
proc ts_node_prev_named_sibling*(a1: TSNode): TSNode {.importc, header: headerapi.}
proc ts_node_first_child_for_byte*(a1: TSNode; a2: uint32): TSNode {.importc,
    header: headerapi.}
proc ts_node_first_named_child_for_byte*(a1: TSNode; a2: uint32): TSNode {.importc,
    header: headerapi.}
proc ts_node_descendant_for_byte_range*(a1: TSNode; a2: uint32; a3: uint32): TSNode {.
    importc, header: headerapi.}
proc ts_node_named_descendant_for_byte_range*(a1: TSNode; a2: uint32; a3: uint32): TSNode {.
    importc, header: headerapi.}
proc ts_node_descendant_for_point_range*(a1: TSNode; a2: TSPoint; a3: TSPoint): TSNode {.
    importc, header: headerapi.}
proc ts_node_named_descendant_for_point_range*(a1: TSNode; a2: TSPoint; a3: TSPoint): TSNode {.
    importc, header: headerapi.}
proc ts_node_edit*(a1: ptr TSNode; a2: ptr TSInputEdit) {.importc, header: headerapi.}
proc ts_tree_cursor_new*(a1: TSNode): TSTreeCursor {.importc, header: headerapi.}
proc ts_tree_cursor_delete*(a1: ptr TSTreeCursor) {.importc, header: headerapi.}
proc ts_tree_cursor_reset*(a1: ptr TSTreeCursor; a2: TSNode) {.importc,
    header: headerapi.}
proc ts_tree_cursor_current_node*(a1: ptr TSTreeCursor): TSNode {.importc,
    header: headerapi.}
proc ts_tree_cursor_goto_parent*(a1: ptr TSTreeCursor): bool {.importc,
    header: headerapi.}
proc ts_tree_cursor_goto_next_sibling*(a1: ptr TSTreeCursor): bool {.importc,
    header: headerapi.}
proc ts_tree_cursor_goto_first_child*(a1: ptr TSTreeCursor): bool {.importc,
    header: headerapi.}
proc ts_tree_cursor_goto_first_child_for_byte*(a1: ptr TSTreeCursor; a2: uint32): int64 {.
    importc, header: headerapi.}
proc ts_language_symbol_count*(a1: ptr TSLanguage): uint32 {.importc,
    header: headerapi.}
proc ts_language_symbol_name*(a1: ptr TSLanguage; a2: TSSymbol): cstring {.importc,
    header: headerapi.}
proc ts_language_symbol_for_name*(a1: ptr TSLanguage; a2: cstring): TSSymbol {.importc,
    header: headerapi.}
proc ts_language_symbol_type*(a1: ptr TSLanguage; a2: TSSymbol): TSSymbolType {.
    importc, header: headerapi.}
proc ts_language_version*(a1: ptr TSLanguage): uint32 {.importc, header: headerapi.}
