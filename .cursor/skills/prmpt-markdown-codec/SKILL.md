---
name: prmpt-markdown-codec
description: Guide safe updates to Prmpt Markdown import/export and inline mark parsing. Use when changing markdown_codec.dart, document model mapping, GFM compatibility, or round-trip behavior between source text and block document.
---

# Prmpt Markdown Codec

## Scope

Use this skill for changes in:
- `lib/src/editor/markdown_codec.dart`
- `lib/src/editor/document.dart` (when codec mapping needs model updates)

## Required Invariants

1. Round-trip should remain stable for supported syntax:
   - Markdown -> Document -> Markdown
2. Keep GitHub Flavored Markdown compatibility (`ExtensionSet.gitHubFlavored`).
3. Inline marks (`bold`, `italic`, `strike`, `code`, `link`, `footnoteRef`) must keep correct ranges.
4. Sanitization behavior must remain deterministic (line endings, zero-width chars, spaces).

## Change Workflow

1. Add or adjust parsing/serialization logic in the codec.
2. Ensure document model still represents block and inline semantics cleanly.
3. Add or update unit tests first for new syntax or bugfix cases.
4. Validate both markdown export and html export impact.

## Test Focus

Prioritize in `test/markdown_codec_test.dart`:
- Import/export round-trip
- Inline mark offsets after parsing
- Edge cases for tables, task lists, footnotes, code fences
- Plain text sanitization cases

## Verification Commands

```bash
flutter test test/markdown_codec_test.dart
flutter analyze
```

## Related References

- `AGENTS.md`
- `CLAUDE.md`
