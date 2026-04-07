# AGENTS.md - Prmpt Project Guide

This file provides essential guidance for AI coding agents working with the **Prmpt** codebase.

## Project Overview

**Prmpt** is a Flutter cross-platform application that implements a Notion-style, true single-view WYSIWYG Markdown editor. The editor follows a block-based architecture where each paragraph, heading, list, table, code fence, image, or footnote is an independent block that can be reordered, converted, and edited inline.

### Key Characteristics

- **True WYSIWYG**: Rendering happens directly inside the editing surface — there is no separate preview pane in WYSIWYG mode
- **Block-based model**: Document is a `List<MarkdownBlock>`; each block has a `type`, `id`, and type-specific data
- **Dual modes**: WYSIWYG mode (single view) and Source mode (split-pane with live preview)
- **Slash commands**: Type `/` at the start of a paragraph to open a command palette for block conversion
- **Inline auto-rendering**: Raw Markdown syntax (`**bold**`, `` `code` ``, `[label](url)`) automatically converts to hidden marks

### Technology Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.0+ (Dart ^3.10.8) |
| State Management | `ChangeNotifier` (built-in Flutter) |
| Markdown Parsing | `markdown` package with `ExtensionSet.gitHubFlavored` |
| Math Rendering | `flutter_math_fork` |
| Markdown Widget | `flutter_markdown` |
| Dev Tools | `ume` (debugging overlay), `flutter_lints` |

### Supported Platforms

- iOS
- Android
- Web
- Windows
- macOS

## Project Structure

```
lib/
├── main.dart                     # App entry point, UME plugin registration
└── src/editor/
    ├── editor_screen.dart        # UI layer (~3000 lines)
    ├── controller.dart           # Business logic & state management
    ├── document.dart             # Immutable data models
    └── markdown_codec.dart       # Bidirectional Markdown/Document conversion

test/
├── markdown_codec_test.dart      # Unit tests for codec
└── widget_test.dart              # Widget/integration tests

docs/
├── require.md                    # Chinese requirements (V1.1)
└── deep-research-report.md       # Technical research & architecture
```

## Architecture Details

### Data Models (`document.dart`)

| Class | Purpose |
|-------|---------|
| `MarkdownDocument` | Immutable container for `List<MarkdownBlock>` |
| `MarkdownBlock` | Individual block with `id`, `type`, and type-specific data (`text`, `items`, `rows`, `code`, `url`, `alt`, etc.) |
| `StyledTextValue` | Plain text + list of `InlineMark` for inline formatting |
| `InlineMark` | Start/end offsets + type (bold, italic, strike, code, link, footnoteRef) |
| `MarkdownListItem` | List item with `content` (StyledTextValue) and optional `checked` |

**Block Types** (`MarkdownBlockType`):
- `heading`, `paragraph`, `quote`
- `bulletList`, `orderedList`, `taskList`
- `codeFence`, `table`, `image`, `footnote`, `thematicBreak`

### Controller (`controller.dart`)

`MarkdownEditorController` extends `ChangeNotifier` and provides:

- Document state: `_document`, `_rawMarkdown`
- Undo/redo stacks: `_undoStack`, `_redoStack` (max 120 entries)
- Block operations: `addBlock`, `deleteBlock`, `moveBlock`, `reorderBlock`, `duplicateBlock`
- Content updates: `updateParagraphLikeBlock`, `updateListItem`, `updateTableCell`, `updateCode`, etc.
- Block conversion: `convertBlock`, `convertBlockToHeading`, `splitBlock`, `mergeBlockWithNext/Previous`
- Live editing boundary: `beginLiveEditing()` / `endLiveEditing()` to prevent undo-stack spam

### Codec (`markdown_codec.dart`)

Bidirectional conversion between Markdown and the document model:

- `importMarkdown()`: Parse Markdown string to `MarkdownDocument`
- `exportMarkdown()`: Serialize `MarkdownDocument` to Markdown string
- `exportHtml()`: Convert to HTML using GitHub Flavored Markdown
- `parseInlineMarkdown()`: Parse inline syntax to `StyledTextValue` with marks
- `inlineToMarkdown()`: Serialize `StyledTextValue` back to Markdown
- `buildParagraphLikeBlockFromInput()`: Auto-detect block type from user input

### UI Layer (`editor_screen.dart`)

| Widget | Responsibility |
|--------|----------------|
| `PrmptApp` | Root MaterialApp with theme configuration |
| `MarkdownEditorScreen` | Main screen with toolbar and mode switching |
| `MarkdownWidget` | ReorderableListView of block editors |
| `_MarkdownBlockEditor` | Per-block editing surface with drag handle and actions |
| `_RichMarkdownField` | TextField with inline style rendering via `_RichMarkdownController` |
| `_PlainMultilineField` | Plain text input for code blocks |
| `_SourcePane` / `_SourcePreview` | Source mode split-pane editor |
| `_SlashCommandPalette` | `/` command menu for block type selection |

## Build and Development Commands

```bash
# Install dependencies
flutter pub get

# Run the app (all platforms supported)
flutter run

# Run tests
flutter test                    # All tests
flutter test test/markdown_codec_test.dart    # Single test file

# Static analysis
flutter analyze

# Build for production
flutter build ios
flutter build android
flutter build macos
flutter build windows
flutter build web
```

## Testing Strategy

### Unit Tests (`test/markdown_codec_test.dart`)

- Import/export round-trips
- Inline parsing (bold, italic, code, links, footnotes)
- Block type auto-detection from input triggers
- HTML generation with GFM structures
- Text sanitization

### Widget Tests (`test/widget_test.dart`)

- Mode switching (WYSIWYG ↔ Source)
- Slash command palette interaction
- Block type conversion via typing triggers (`# `, `- `, etc.)
- Text selection and formatting toolbar
- Undo/redo accessibility

## Code Style Guidelines

### Dart/Flutter Conventions

- Uses `package:flutter_lints/flutter.yaml` as base lint rules
- Follows standard Flutter naming: `PascalCase` for classes, `camelCase` for methods/variables
- Private members prefixed with `_`
- Prefer single quotes for strings
- Trailing commas for multi-line collections

### Project-Specific Patterns

1. **Immutable blocks**: All `MarkdownBlock` and `StyledTextValue` objects are immutable; mutations create new instances via `copyWith()`

2. **Unmodifiable lists**: Document blocks stored as `List<MarkdownBlock>.unmodifiable()` to prevent accidental mutation

3. **Clone before mutate**: Controller calls `_recordHistory()` (which clones document) before making changes

4. **Live editing boundary**: 
   - Call `beginLiveEditing()` when user starts typing
   - Call `endLiveEditing()` when field loses focus
   - Prevents undo-stack spam during continuous typing

5. **Focus management**: Controller tracks `_pendingFocusBlockId` for post-build focus requests via `WidgetsBinding.instance.addPostFrameCallback()`

6. **Controller synchronization**: When modifying text programmatically, watch for cursor jumps caused by out-of-sync controller values

## Important Implementation Details

### Mutable Controllers Inside Immutable Blocks

Blocks themselves are immutable, but Flutter `TextEditingController` instances backing each block field are stateful. These must be synced carefully via `didUpdateWidget`. When modifying code, watch for cursor jumps caused by out-of-sync controller values.

### Inline Syntax Auto-Rendering

The `_transformInlineInput` method in `editor_screen.dart` listens to field changes and automatically converts raw Markdown syntax into hidden marks, adjusting cursor position after replacement.

### GFM Export/Import

`MarkdownCodec` uses the `markdown` package with `ExtensionSet.gitHubFlavored` for inline parsing and HTML export. Block-level parsing is custom line-by-line Dart code (tables, task lists, footnotes, code fences).

### Undo/Redo Stack

- Maximum 120 entries in undo stack
- Stack is cleared on `replaceSource()`, `clearDocument()`, `addBlock()`, `deleteBlock()`, etc.
- `beginLiveEditing()` captures state once; changes during live edit don't push new history entries

## Security Considerations

- Clipboard operations sanitize input via `MarkdownCodec.sanitizePlainText()`:
  - Normalizes line endings (`\r\n` → `\n`, `\r` → `\n`)
  - Removes zero-width characters (`\u200B-\u200D`, `\uFEFF`)
  - Replaces non-breaking spaces (`\u00A0` → regular space)
- No external network requests in core editor (images use provided URLs)
- Link taps copy URL to clipboard rather than opening browser directly

## Documentation References

- `docs/require.md` — Original Chinese requirements (V1.1)
- `docs/deep-research-report.md` — Technical research covering parser strategy, document model (tree + Delta), renderer design, virtualization, and phased implementation plan

## Dependencies

See `pubspec.yaml` for full list. Key dependencies:

| Package | Purpose |
|---------|---------|
| `flutter_math_fork` | LaTeX math rendering |
| `markdown` | GFM parsing |
| `flutter_markdown` | Markdown widget rendering |
| `ume` | Development debugging tools |
| `flutter_lints` | Static analysis rules |
