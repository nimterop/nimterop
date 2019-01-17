{.experimental: "codeReordering".}

import strutils

import ".."/setup

static:
  treesitterSetup()

const sourcePath = currentSourcePath().split({'\\', '/'})[0..^4].join("/") & "/inc/treesitter"

{.passC: "-std=c11 -DUTF8PROC_STATIC".}
{.passC: "-I$1/include" % sourcePath.}
{.passC: "-I$1/src" % sourcePath.}
{.passC: "-I$1/../utf8proc" % sourcePath.}
{.compile: sourcePath & "/src/runtime/runtime.c".}

type TSInputEncoding* = distinct int
converter enumToInt(en: TSInputEncoding): int {.used.} = en.int

type TSSymbolType* = distinct int
converter enumToInt(en: TSSymbolType): int {.used.} = en.int

type TSLogType* = distinct int
converter enumToInt(en: TSLogType): int {.used.} = en.int

const
  headerruntime = sourcePath & "/include/tree_sitter/runtime.h"
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
  TSPoint* {.importc: "TSPoint", header: headerruntime, bycopy.} = object
    row*: uint32
    column*: uint32
  TSRange* {.importc: "TSRange", header: headerruntime, bycopy.} = object
    start_point*: TSPoint
    end_point*: TSPoint
    start_byte*: uint32
    end_byte*: uint32
  TSInput* {.importc: "TSInput", header: headerruntime, bycopy.} = object
    payload*: pointer
    read*: proc(byte_index: uint32,position: TSPoint,bytes_read: ptr uint32): cchar {.nimcall.}
    encoding*: TSInputEncoding
  TSLogger* {.importc: "TSLogger", header: headerruntime, bycopy.} = object
    payload*: pointer
    log*: proc(a1: TSLogType,a2: cstring) {.nimcall.}
  TSInputEdit* {.importc: "TSInputEdit", header: headerruntime, bycopy.} = object
    start_byte*: uint32
    old_end_byte*: uint32
    new_end_byte*: uint32
    start_point*: TSPoint
    old_end_point*: TSPoint
    new_end_point*: TSPoint
  TSNode* {.importc: "TSNode", header: headerruntime, bycopy.} = object
    context*: array[4, uint32]
    id*: pointer
    tree*: ptr TSTree
  TSTreeCursor* {.importc: "TSTreeCursor", header: headerruntime, bycopy.} = object
    tree*: pointer
    id*: pointer
    context*: array[2, uint32]

proc ts_parser_new*(): ptr TSParser {.importc: "ts_parser_new", header: headerruntime.}
proc ts_parser_delete*(a1: ptr TSParser) {.importc: "ts_parser_delete", header: headerruntime.}
proc ts_parser_language*(a1: ptr TSParser): ptr TSLanguage {.importc: "ts_parser_language", header: headerruntime.}
proc ts_parser_set_language*(a1: ptr TSParser,a2: ptr TSLanguage): bool {.importc: "ts_parser_set_language", header: headerruntime.}
proc ts_parser_logger*(a1: ptr TSParser): TSLogger {.importc: "ts_parser_logger", header: headerruntime.}
proc ts_parser_set_logger*(a1: ptr TSParser,a2: TSLogger) {.importc: "ts_parser_set_logger", header: headerruntime.}
proc ts_parser_print_dot_graphs*(a1: ptr TSParser,a2: ptr FILE) {.importc: "ts_parser_print_dot_graphs", header: headerruntime.}
proc ts_parser_halt_on_error*(a1: ptr TSParser,a2: bool) {.importc: "ts_parser_halt_on_error", header: headerruntime.}
proc ts_parser_parse*(a1: ptr TSParser,a2: ptr TSTree,a3: TSInput): ptr TSTree {.importc: "ts_parser_parse", header: headerruntime.}
proc ts_parser_parse_string*(a1: ptr TSParser,a2: ptr TSTree,a3: cstring,a4: uint32): ptr TSTree {.importc: "ts_parser_parse_string", header: headerruntime.}
proc ts_parser_parse_string_encoding*(a1: ptr TSParser,a2: ptr TSTree,a3: cstring,a4: uint32,a5: TSInputEncoding): ptr TSTree {.importc: "ts_parser_parse_string_encoding", header: headerruntime.}
proc ts_parser_enabled*(a1: ptr TSParser): bool {.importc: "ts_parser_enabled", header: headerruntime.}
proc ts_parser_set_enabled*(a1: ptr TSParser,a2: bool) {.importc: "ts_parser_set_enabled", header: headerruntime.}
proc ts_parser_operation_limit*(a1: ptr TSParser): uint {.importc: "ts_parser_operation_limit", header: headerruntime.}
proc ts_parser_set_operation_limit*(a1: ptr TSParser,a2: uint) {.importc: "ts_parser_set_operation_limit", header: headerruntime.}
proc ts_parser_reset*(a1: ptr TSParser) {.importc: "ts_parser_reset", header: headerruntime.}
proc ts_parser_set_included_ranges*(a1: ptr TSParser,a2: ptr TSRange,a3: uint32) {.importc: "ts_parser_set_included_ranges", header: headerruntime.}
proc ts_parser_included_ranges*(a1: ptr TSParser,a2: ptr uint32): ptr TSRange {.importc: "ts_parser_included_ranges", header: headerruntime.}
proc ts_tree_copy*(a1: ptr TSTree): ptr TSTree {.importc: "ts_tree_copy", header: headerruntime.}
proc ts_tree_delete*(a1: ptr TSTree) {.importc: "ts_tree_delete", header: headerruntime.}
proc ts_tree_root_node*(a1: ptr TSTree): TSNode {.importc: "ts_tree_root_node", header: headerruntime.}
proc ts_tree_edit*(a1: ptr TSTree,a2: ptr TSInputEdit) {.importc: "ts_tree_edit", header: headerruntime.}
proc ts_tree_get_changed_ranges*(a1: ptr TSTree,a2: ptr TSTree,a3: ptr uint32): ptr TSRange {.importc: "ts_tree_get_changed_ranges", header: headerruntime.}
proc ts_tree_print_dot_graph*(a1: ptr TSTree,a2: ptr FILE) {.importc: "ts_tree_print_dot_graph", header: headerruntime.}
proc ts_tree_language*(a1: ptr TSTree): ptr TSLanguage {.importc: "ts_tree_language", header: headerruntime.}
proc ts_node_start_byte*(a1: TSNode): uint32 {.importc: "ts_node_start_byte", header: headerruntime.}
proc ts_node_start_point*(a1: TSNode): TSPoint {.importc: "ts_node_start_point", header: headerruntime.}
proc ts_node_end_byte*(a1: TSNode): uint32 {.importc: "ts_node_end_byte", header: headerruntime.}
proc ts_node_end_point*(a1: TSNode): TSPoint {.importc: "ts_node_end_point", header: headerruntime.}
proc ts_node_symbol*(a1: TSNode): TSSymbol {.importc: "ts_node_symbol", header: headerruntime.}
proc ts_node_type*(a1: TSNode): cstring {.importc: "ts_node_type", header: headerruntime.}
proc ts_node_string*(a1: TSNode): cstring {.importc: "ts_node_string", header: headerruntime.}
proc ts_node_eq*(a1: TSNode,a2: TSNode): bool {.importc: "ts_node_eq", header: headerruntime.}
proc ts_node_is_null*(a1: TSNode): bool {.importc: "ts_node_is_null", header: headerruntime.}
proc ts_node_is_named*(a1: TSNode): bool {.importc: "ts_node_is_named", header: headerruntime.}
proc ts_node_is_missing*(a1: TSNode): bool {.importc: "ts_node_is_missing", header: headerruntime.}
proc ts_node_has_changes*(a1: TSNode): bool {.importc: "ts_node_has_changes", header: headerruntime.}
proc ts_node_has_error*(a1: TSNode): bool {.importc: "ts_node_has_error", header: headerruntime.}
proc ts_node_parent*(a1: TSNode): TSNode {.importc: "ts_node_parent", header: headerruntime.}
proc ts_node_child*(a1: TSNode,a2: uint32): TSNode {.importc: "ts_node_child", header: headerruntime.}
proc ts_node_named_child*(a1: TSNode,a2: uint32): TSNode {.importc: "ts_node_named_child", header: headerruntime.}
proc ts_node_child_count*(a1: TSNode): uint32 {.importc: "ts_node_child_count", header: headerruntime.}
proc ts_node_named_child_count*(a1: TSNode): uint32 {.importc: "ts_node_named_child_count", header: headerruntime.}
proc ts_node_next_sibling*(a1: TSNode): TSNode {.importc: "ts_node_next_sibling", header: headerruntime.}
proc ts_node_next_named_sibling*(a1: TSNode): TSNode {.importc: "ts_node_next_named_sibling", header: headerruntime.}
proc ts_node_prev_sibling*(a1: TSNode): TSNode {.importc: "ts_node_prev_sibling", header: headerruntime.}
proc ts_node_prev_named_sibling*(a1: TSNode): TSNode {.importc: "ts_node_prev_named_sibling", header: headerruntime.}
proc ts_node_first_child_for_byte*(a1: TSNode,a2: uint32): TSNode {.importc: "ts_node_first_child_for_byte", header: headerruntime.}
proc ts_node_first_named_child_for_byte*(a1: TSNode,a2: uint32): TSNode {.importc: "ts_node_first_named_child_for_byte", header: headerruntime.}
proc ts_node_descendant_for_byte_range*(a1: TSNode,a2: uint32,a3: uint32): TSNode {.importc: "ts_node_descendant_for_byte_range", header: headerruntime.}
proc ts_node_named_descendant_for_byte_range*(a1: TSNode,a2: uint32,a3: uint32): TSNode {.importc: "ts_node_named_descendant_for_byte_range", header: headerruntime.}
proc ts_node_descendant_for_point_range*(a1: TSNode,a2: TSPoint,a3: TSPoint): TSNode {.importc: "ts_node_descendant_for_point_range", header: headerruntime.}
proc ts_node_named_descendant_for_point_range*(a1: TSNode,a2: TSPoint,a3: TSPoint): TSNode {.importc: "ts_node_named_descendant_for_point_range", header: headerruntime.}
proc ts_node_edit*(a1: ptr TSNode,a2: ptr TSInputEdit) {.importc: "ts_node_edit", header: headerruntime.}
proc ts_tree_cursor_new*(a1: TSNode): TSTreeCursor {.importc: "ts_tree_cursor_new", header: headerruntime.}
proc ts_tree_cursor_delete*(a1: ptr TSTreeCursor) {.importc: "ts_tree_cursor_delete", header: headerruntime.}
proc ts_tree_cursor_reset*(a1: ptr TSTreeCursor,a2: TSNode) {.importc: "ts_tree_cursor_reset", header: headerruntime.}
proc ts_tree_cursor_current_node*(a1: ptr TSTreeCursor): TSNode {.importc: "ts_tree_cursor_current_node", header: headerruntime.}
proc ts_tree_cursor_goto_parent*(a1: ptr TSTreeCursor): bool {.importc: "ts_tree_cursor_goto_parent", header: headerruntime.}
proc ts_tree_cursor_goto_next_sibling*(a1: ptr TSTreeCursor): bool {.importc: "ts_tree_cursor_goto_next_sibling", header: headerruntime.}
proc ts_tree_cursor_goto_first_child*(a1: ptr TSTreeCursor): bool {.importc: "ts_tree_cursor_goto_first_child", header: headerruntime.}
proc ts_tree_cursor_goto_first_child_for_byte*(a1: ptr TSTreeCursor,a2: uint32): int64 {.importc: "ts_tree_cursor_goto_first_child_for_byte", header: headerruntime.}
proc ts_language_symbol_count*(a1: ptr TSLanguage): uint32 {.importc: "ts_language_symbol_count", header: headerruntime.}
proc ts_language_symbol_name*(a1: ptr TSLanguage,a2: TSSymbol): cstring {.importc: "ts_language_symbol_name", header: headerruntime.}
proc ts_language_symbol_for_name*(a1: ptr TSLanguage,a2: cstring): TSSymbol {.importc: "ts_language_symbol_for_name", header: headerruntime.}
proc ts_language_symbol_type*(a1: ptr TSLanguage,a2: TSSymbol): TSSymbolType {.importc: "ts_language_symbol_type", header: headerruntime.}
proc ts_language_version*(a1: ptr TSLanguage): uint32 {.importc: "ts_language_version", header: headerruntime.}

