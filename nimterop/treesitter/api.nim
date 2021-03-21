{.experimental: "codeReordering".}

import strutils, os

include ".."/enumtype
import ".."/[paths, setup]

static:
  treesitterSetup()

const sourcePath = cacheDir / "treesitter" / "lib"

when defined(Linux) and defined(gcc):
  {.passC: "-std=c11".}

{.passC: "-I\"$1\"" % (sourcePath / "include").}
{.passC: "-I\"$1\"" % (sourcePath / "src").}

{.compile: sourcePath / "src" / "lib.c".}

### Generated below

{.push hint[ConvFromXtoItselfNotNeeded]: off.}
{.pragma: impapiHdr, header: sourcePath / "include" / "tree_sitter" / "api.h".}

defineEnum(TSInputEncoding)
defineEnum(TSSymbolType)
defineEnum(TSLogType)
defineEnum(TSQueryPredicateStepType)
defineEnum(TSQueryError)

const
  TREE_SITTER_LANGUAGE_VERSION* = 11
  TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION* = 9
  TSInputEncodingUTF8* = (0).TSInputEncoding
  TSInputEncodingUTF16* = (TSInputEncodingUTF8 + 1).TSInputEncoding
  TSSymbolTypeRegular* = (0).TSSymbolType
  TSSymbolTypeAnonymous* = (TSSymbolTypeRegular + 1).TSSymbolType
  TSSymbolTypeAuxiliary* = (TSSymbolTypeAnonymous + 1).TSSymbolType
  TSLogTypeParse* = (0).TSLogType
  TSLogTypeLex* = (TSLogTypeParse + 1).TSLogType
  TSQueryPredicateStepTypeDone* = (0).TSQueryPredicateStepType
  TSQueryPredicateStepTypeCapture* = (TSQueryPredicateStepTypeDone + 1).TSQueryPredicateStepType
  TSQueryPredicateStepTypeString* = (TSQueryPredicateStepTypeCapture + 1).TSQueryPredicateStepType
  TSQueryErrorNone* = (0).TSQueryError
  TSQueryErrorSyntax* = (TSQueryErrorNone + 1).TSQueryError
  TSQueryErrorNodeType* = (TSQueryErrorSyntax + 1).TSQueryError
  TSQueryErrorField* = (TSQueryErrorNodeType + 1).TSQueryError
  TSQueryErrorCapture* = (TSQueryErrorField + 1).TSQueryError

type
  TSSymbol* {.importc, impapiHdr.} = uint16
  TSFieldId* {.importc, impapiHdr.} = uint16
  TSLanguage* {.importc, impapiHdr, incompleteStruct.} = object
  TSParser* {.importc, impapiHdr, incompleteStruct.} = object
  TSTree* {.importc, impapiHdr, incompleteStruct.} = object
  TSQuery* {.importc, impapiHdr, incompleteStruct.} = object
  TSQueryCursor* {.importc, impapiHdr, incompleteStruct.} = object
  TSPoint* {.bycopy, importc, impapiHdr.} = object
    row*: uint32
    column*: uint32

  TSRange* {.bycopy, importc, impapiHdr.} = object
    start_point*: TSPoint
    end_point*: TSPoint
    start_byte*: uint32
    end_byte*: uint32

  TSInput* {.bycopy, importc, impapiHdr.} = object
    payload*: pointer
    read*: proc (payload: pointer; byte_index: uint32; position: TSPoint;
               bytes_read: ptr uint32): cstring {.cdecl.}
    encoding*: TSInputEncoding

  TSLogger* {.bycopy, importc, impapiHdr.} = object
    payload*: pointer
    log*: proc (payload: pointer; a2: TSLogType; a3: cstring) {.cdecl.}

  TSInputEdit* {.bycopy, importc, impapiHdr.} = object
    start_byte*: uint32
    old_end_byte*: uint32
    new_end_byte*: uint32
    start_point*: TSPoint
    old_end_point*: TSPoint
    new_end_point*: TSPoint

  TSNode* {.bycopy, importc, impapiHdr.} = object
    context*: array[4, uint32]
    id*: pointer
    tree*: ptr TSTree

  TSTreeCursor* {.bycopy, importc, impapiHdr.} = object
    tree*: pointer
    id*: pointer
    context*: array[2, uint32]

  TSQueryCapture* {.bycopy, importc, impapiHdr.} = object
    node*: TSNode
    index*: uint32

  TSQueryMatch* {.bycopy, importc, impapiHdr.} = object
    id*: uint32
    pattern_index*: uint16
    capture_count*: uint16
    captures*: ptr TSQueryCapture

  TSQueryPredicateStep* {.bycopy, importc, impapiHdr.} = object
    `type`*: TSQueryPredicateStepType
    value_id*: uint32

proc ts_parser_new*(): ptr TSParser {.importc, cdecl, impapiHdr.}
proc ts_parser_delete*(parser: ptr TSParser) {.importc, cdecl, impapiHdr.}
proc ts_parser_set_language*(self: ptr TSParser; language: ptr TSLanguage): bool {.
    importc, cdecl, impapiHdr.}
proc ts_parser_language*(self: ptr TSParser): ptr TSLanguage {.importc, cdecl, impapiHdr.}
proc ts_parser_set_included_ranges*(self: ptr TSParser; ranges: ptr TSRange;
                                   length: uint32) {.importc, cdecl, impapiHdr.}
proc ts_parser_included_ranges*(self: ptr TSParser; length: ptr uint32): ptr TSRange {.
    importc, cdecl, impapiHdr.}
proc ts_parser_parse*(self: ptr TSParser; old_tree: ptr TSTree; input: TSInput): ptr TSTree {.
    importc, cdecl, impapiHdr.}
proc ts_parser_parse_string*(self: ptr TSParser; old_tree: ptr TSTree; string: cstring;
                            length: uint32): ptr TSTree {.importc, cdecl, impapiHdr.}
proc ts_parser_parse_string_encoding*(self: ptr TSParser; old_tree: ptr TSTree;
                                     string: cstring; length: uint32;
                                     encoding: TSInputEncoding): ptr TSTree {.
    importc, cdecl, impapiHdr.}
proc ts_parser_reset*(self: ptr TSParser) {.importc, cdecl, impapiHdr.}
proc ts_parser_set_timeout_micros*(self: ptr TSParser; timeout: uint64) {.importc,
    cdecl, impapiHdr.}
proc ts_parser_timeout_micros*(self: ptr TSParser): uint64 {.importc, cdecl, impapiHdr.}
proc ts_parser_set_cancellation_flag*(self: ptr TSParser; flag: ptr uint) {.importc,
    cdecl, impapiHdr.}
proc ts_parser_cancellation_flag*(self: ptr TSParser): ptr uint {.importc, cdecl,
    impapiHdr.}
proc ts_parser_set_logger*(self: ptr TSParser; logger: TSLogger) {.importc, cdecl,
    impapiHdr.}
proc ts_parser_logger*(self: ptr TSParser): TSLogger {.importc, cdecl, impapiHdr.}
proc ts_parser_print_dot_graphs*(self: ptr TSParser; file: cint) {.importc, cdecl,
    impapiHdr.}
proc ts_parser_halt_on_error*(self: ptr TSParser; halt: bool) {.importc, cdecl,
    impapiHdr.}
proc ts_tree_copy*(self: ptr TSTree): ptr TSTree {.importc, cdecl, impapiHdr.}
proc ts_tree_delete*(self: ptr TSTree) {.importc, cdecl, impapiHdr.}
proc ts_tree_root_node*(self: ptr TSTree): TSNode {.importc, cdecl, impapiHdr.}
proc ts_tree_language*(a1: ptr TSTree): ptr TSLanguage {.importc, cdecl, impapiHdr.}
proc ts_tree_edit*(self: ptr TSTree; edit: ptr TSInputEdit) {.importc, cdecl, impapiHdr.}
proc ts_tree_get_changed_ranges*(old_tree: ptr TSTree; new_tree: ptr TSTree;
                                length: ptr uint32): ptr TSRange {.importc, cdecl,
    impapiHdr.}
proc ts_tree_print_dot_graph*(a1: ptr TSTree; a2: File) {.importc, cdecl, impapiHdr.}
proc ts_node_type*(a1: TSNode): cstring {.importc, cdecl, impapiHdr.}
proc ts_node_symbol*(a1: TSNode): TSSymbol {.importc, cdecl, impapiHdr.}
proc ts_node_start_byte*(a1: TSNode): uint32 {.importc, cdecl, impapiHdr.}
proc ts_node_start_point*(a1: TSNode): TSPoint {.importc, cdecl, impapiHdr.}
proc ts_node_end_byte*(a1: TSNode): uint32 {.importc, cdecl, impapiHdr.}
proc ts_node_end_point*(a1: TSNode): TSPoint {.importc, cdecl, impapiHdr.}
proc ts_node_string*(a1: TSNode): cstring {.importc, cdecl, impapiHdr.}
proc ts_node_is_null*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_is_named*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_is_missing*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_is_extra*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_has_changes*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_has_error*(a1: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_node_parent*(a1: TSNode): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_child*(a1: TSNode; a2: uint32): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_child_count*(a1: TSNode): uint32 {.importc, cdecl, impapiHdr.}
proc ts_node_named_child*(a1: TSNode; a2: uint32): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_named_child_count*(a1: TSNode): uint32 {.importc, cdecl, impapiHdr.}
proc ts_node_child_by_field_name*(self: TSNode; field_name: cstring;
                                 field_name_length: uint32): TSNode {.importc,
    cdecl, impapiHdr.}
proc ts_node_child_by_field_id*(a1: TSNode; a2: TSFieldId): TSNode {.importc, cdecl,
    impapiHdr.}
proc ts_node_next_sibling*(a1: TSNode): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_prev_sibling*(a1: TSNode): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_next_named_sibling*(a1: TSNode): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_prev_named_sibling*(a1: TSNode): TSNode {.importc, cdecl, impapiHdr.}
proc ts_node_first_child_for_byte*(a1: TSNode; a2: uint32): TSNode {.importc, cdecl,
    impapiHdr.}
proc ts_node_first_named_child_for_byte*(a1: TSNode; a2: uint32): TSNode {.importc,
    cdecl, impapiHdr.}
proc ts_node_descendant_for_byte_range*(a1: TSNode; a2: uint32; a3: uint32): TSNode {.
    importc, cdecl, impapiHdr.}
proc ts_node_descendant_for_point_range*(a1: TSNode; a2: TSPoint; a3: TSPoint): TSNode {.
    importc, cdecl, impapiHdr.}
proc ts_node_named_descendant_for_byte_range*(a1: TSNode; a2: uint32; a3: uint32): TSNode {.
    importc, cdecl, impapiHdr.}
proc ts_node_named_descendant_for_point_range*(a1: TSNode; a2: TSPoint; a3: TSPoint): TSNode {.
    importc, cdecl, impapiHdr.}
proc ts_node_edit*(a1: ptr TSNode; a2: ptr TSInputEdit) {.importc, cdecl, impapiHdr.}
proc ts_node_eq*(a1: TSNode; a2: TSNode): bool {.importc, cdecl, impapiHdr.}
proc ts_tree_cursor_new*(a1: TSNode): TSTreeCursor {.importc, cdecl, impapiHdr.}
proc ts_tree_cursor_delete*(a1: ptr TSTreeCursor) {.importc, cdecl, impapiHdr.}
proc ts_tree_cursor_reset*(a1: ptr TSTreeCursor; a2: TSNode) {.importc, cdecl, impapiHdr.}
proc ts_tree_cursor_current_node*(a1: ptr TSTreeCursor): TSNode {.importc, cdecl,
    impapiHdr.}
proc ts_tree_cursor_current_field_name*(a1: ptr TSTreeCursor): cstring {.importc,
    cdecl, impapiHdr.}
proc ts_tree_cursor_current_field_id*(a1: ptr TSTreeCursor): TSFieldId {.importc,
    cdecl, impapiHdr.}
proc ts_tree_cursor_goto_parent*(a1: ptr TSTreeCursor): bool {.importc, cdecl,
    impapiHdr.}
proc ts_tree_cursor_goto_next_sibling*(a1: ptr TSTreeCursor): bool {.importc, cdecl,
    impapiHdr.}
proc ts_tree_cursor_goto_first_child*(a1: ptr TSTreeCursor): bool {.importc, cdecl,
    impapiHdr.}
proc ts_tree_cursor_goto_first_child_for_byte*(a1: ptr TSTreeCursor; a2: uint32): int64 {.
    importc, cdecl, impapiHdr.}
proc ts_tree_cursor_copy*(a1: ptr TSTreeCursor): TSTreeCursor {.importc, cdecl,
    impapiHdr.}
proc ts_query_new*(language: ptr TSLanguage; source: cstring; source_len: uint32;
                  error_offset: ptr uint32; error_type: ptr TSQueryError): ptr TSQuery {.
    importc, cdecl, impapiHdr.}
proc ts_query_delete*(a1: ptr TSQuery) {.importc, cdecl, impapiHdr.}
proc ts_query_pattern_count*(a1: ptr TSQuery): uint32 {.importc, cdecl, impapiHdr.}
proc ts_query_capture_count*(a1: ptr TSQuery): uint32 {.importc, cdecl, impapiHdr.}
proc ts_query_string_count*(a1: ptr TSQuery): uint32 {.importc, cdecl, impapiHdr.}
proc ts_query_start_byte_for_pattern*(a1: ptr TSQuery; a2: uint32): uint32 {.importc,
    cdecl, impapiHdr.}
proc ts_query_predicates_for_pattern*(self: ptr TSQuery; pattern_index: uint32;
                                     length: ptr uint32): ptr TSQueryPredicateStep {.
    importc, cdecl, impapiHdr.}
proc ts_query_capture_name_for_id*(a1: ptr TSQuery; id: uint32; length: ptr uint32): cstring {.
    importc, cdecl, impapiHdr.}
proc ts_query_string_value_for_id*(a1: ptr TSQuery; id: uint32; length: ptr uint32): cstring {.
    importc, cdecl, impapiHdr.}
proc ts_query_disable_capture*(a1: ptr TSQuery; a2: cstring; a3: uint32) {.importc,
    cdecl, impapiHdr.}
proc ts_query_cursor_new*(): ptr TSQueryCursor {.importc, cdecl, impapiHdr.}
proc ts_query_cursor_delete*(a1: ptr TSQueryCursor) {.importc, cdecl, impapiHdr.}
proc ts_query_cursor_exec*(a1: ptr TSQueryCursor; a2: ptr TSQuery; a3: TSNode) {.importc,
    cdecl, impapiHdr.}
proc ts_query_cursor_set_byte_range*(a1: ptr TSQueryCursor; a2: uint32; a3: uint32) {.
    importc, cdecl, impapiHdr.}
proc ts_query_cursor_set_point_range*(a1: ptr TSQueryCursor; a2: TSPoint; a3: TSPoint) {.
    importc, cdecl, impapiHdr.}
proc ts_query_cursor_next_match*(a1: ptr TSQueryCursor; match: ptr TSQueryMatch): bool {.
    importc, cdecl, impapiHdr.}
proc ts_query_cursor_remove_match*(a1: ptr TSQueryCursor; id: uint32) {.importc, cdecl,
    impapiHdr.}
proc ts_query_cursor_next_capture*(a1: ptr TSQueryCursor; match: ptr TSQueryMatch;
                                  capture_index: ptr uint32): bool {.importc, cdecl,
    impapiHdr.}
proc ts_language_symbol_count*(a1: ptr TSLanguage): uint32 {.importc, cdecl, impapiHdr.}
proc ts_language_symbol_name*(a1: ptr TSLanguage; a2: TSSymbol): cstring {.importc,
    cdecl, impapiHdr.}
proc ts_language_symbol_for_name*(self: ptr TSLanguage; string: cstring;
                                 length: uint32; is_named: bool): TSSymbol {.importc,
    cdecl, impapiHdr.}
proc ts_language_field_count*(a1: ptr TSLanguage): uint32 {.importc, cdecl, impapiHdr.}
proc ts_language_field_name_for_id*(a1: ptr TSLanguage; a2: TSFieldId): cstring {.
    importc, cdecl, impapiHdr.}
proc ts_language_field_id_for_name*(a1: ptr TSLanguage; a2: cstring; a3: uint32): TSFieldId {.
    importc, cdecl, impapiHdr.}
proc ts_language_symbol_type*(a1: ptr TSLanguage; a2: TSSymbol): TSSymbolType {.
    importc, cdecl, impapiHdr.}
proc ts_language_version*(a1: ptr TSLanguage): uint32 {.importc, cdecl, impapiHdr.}
{.pop.}
