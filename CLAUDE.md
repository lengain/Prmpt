# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Prmpt** is a Flutter cross-platform app that implements a Notion-style, true single-view WYSIWYG Markdown editor. The editor is block-based: each paragraph, heading, list, table, code fence, image, or footnote is an independent block that can be reordered, converted, and edited inline. Rendering happens directly inside the editing surface — there is no separate preview pane in WYSIWYG mode.

## Common Commands

- Install dependencies: `flutter pub get`
- Run the app: `flutter run`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/markdown_codec_test.dart`
- Lint: `flutter analyze`
- Build for a platform: `flutter build macos` (or `ios`, `android`, `web`, `windows`)

## Architecture

### Layer Layout (`lib/src/editor/`)

| File | Responsibility |
|------|----------------|
| `editor_screen.dart` | All UI widgets: `MarkdownEditorScreen`, `MarkdownWidget`, per-block editor `_MarkdownBlockEditor`, `_RichMarkdownField`, `_PlainMultilineField`, source/preview panes. |
| `controller.dart` | `MarkdownEditorController` (extends `ChangeNotifier`). Holds `_document`, `_rawMarkdown`, undo/redo stacks, and exposes every mutating operation (add/move/delete block, update cell, toggle task, convert block type, etc.). |
| `document.dart` | Immutable data models: `MarkdownDocument`, `MarkdownBlock`, `MarkdownListItem`, `StyledTextValue`, `InlineMark`, `MarkdownBlockType`. |
| `markdown_codec.dart` | Bidirectional conversion between Markdown / HTML and the document model. Also contains `sampleMarkdown` and inline-markdown parsing utilities. |

### Key Design Patterns

- **Block-based model**: A document is a `List<MarkdownBlock>`. Each block has a `type`, `id`, and type-specific data (`text`, `items`, `rows`, `code`, `url`, `alt`, etc.). Blocks are immutable and replaced on every mutation.
- **Inline marks**: `StyledTextValue` stores plain `text` plus a list of `InlineMark` objects (start/end offsets) for bold, italic, strike, code, link, and footnote refs. `editor_screen.dart` uses a custom `_RichMarkdownController` that builds a `TextSpan` from these marks so the user sees rendered styles while typing inside a `TextField`.
- **Inline syntax auto-rendering**: `_transformInlineInput` in `editor_screen.dart` listens to field changes and automatically converts raw Markdown syntax (`**bold**`, `` `code` ``, `[label](url)`, `*italic*`, `~~strike~~`, `[^id]`) into hidden marks, adjusting the cursor position after replacement.
- **Undo / redo**: The controller clones the entire `MarkdownDocument` and pushes it onto an `_undoStack` before each discrete edit. Live editing batches changes without recording history until focus leaves the field.
- **Dual modes**: `EditorMode.wysiwyg` renders a `ReorderableListView` of block cards. `EditorMode.source` shows a raw Markdown textarea with a live GFM preview side-by-side (or stacked on narrow screens).
- **Slash commands**: Typing `/` at the start of a paragraph block opens a local command palette for converting the block to heading, list, table, code, image, etc.

### Important Implementation Details

- **Mutable controllers inside immutable blocks**: Blocks themselves are immutable, but the Flutter `TextEditingController` that backs each block field is stateful and must be synced carefully via `didUpdateWidget`. When modifying code, watch for cursor jumps caused by out-of-sync controller values.
- **Live editing boundary**: `beginLiveEditing()` / `endLiveEditing()` in the controller prevent undo-stack spam while a user is actively typing in a single field.
- **GFM export/import**: `MarkdownCodec` uses the `markdown` package with `ExtensionSet.gitHubFlavored` for inline parsing and HTML export. Block-level parsing is custom line-by-line Dart code (tables, task lists, footnotes, code fences).
- **Tests**: `test/markdown_codec_test.dart` covers import/export round-trips, inline parsing, and HTML generation. `test/widget_test.dart` exercises UI interactions (mode switching, slash commands, WYSIWYG surface checks).

## External Documentation

- `docs/require.md` — Original Chinese requirements document (V1.1) defining the Notion-style WYSIWYG experience, block types, slash commands, and performance targets.
- `docs/deep-research-report.md` — Technical research report covering parser strategy, document model (tree + Delta), renderer design, virtualization, and phased implementation plan.
