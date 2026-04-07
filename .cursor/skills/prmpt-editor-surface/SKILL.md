---
name: prmpt-editor-surface
description: Safely modify the Prmpt block-based WYSIWYG editor surface and controller coordination. Use when changing editor interactions, block operations, focus flow, slash commands, or inline editing behavior in editor_screen.dart and controller.dart.
---

# Prmpt Editor Surface

## Scope

Use this skill for UI and interaction changes in:
- `lib/src/editor/editor_screen.dart`
- `lib/src/editor/controller.dart`

## Guardrails

1. Keep the block model immutable. Update blocks via replacement, not in-place mutation.
2. Respect live editing boundaries:
   - Start edits with `beginLiveEditing()`
   - End edits with `endLiveEditing()` when focus leaves
3. Prevent text controller desync:
   - Sync `TextEditingController` values in lifecycle updates
   - Preserve cursor/selection whenever possible
4. Do not break slash command behavior (`/` at paragraph start).
5. Maintain undo/redo semantics; avoid noisy history entries for continuous typing.

## Change Checklist

- [ ] Interaction change mapped to a specific block type and path
- [ ] Focus transition verified (insert/split/merge/delete cases)
- [ ] Cursor position still stable after auto transform or programmatic updates
- [ ] Undo once returns to expected previous visual/content state
- [ ] Source mode still reflects WYSIWYG changes

## Verification Commands

Run after edits:

```bash
flutter analyze
flutter test test/widget_test.dart
```

## Related References

- `AGENTS.md`
- `CLAUDE.md`
