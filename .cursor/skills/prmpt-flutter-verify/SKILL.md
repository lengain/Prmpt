---
name: prmpt-flutter-verify
description: Run practical verification for Prmpt Flutter editor changes and report evidence. Use before claiming fixes are complete, especially after editing editor, controller, markdown codec, or tests.
---

# Prmpt Flutter Verify

## When To Use

Apply this skill before stating that a change is done or fixed.

## Verification Matrix

Pick the smallest sufficient set based on modified files:

1. `lib/src/editor/markdown_codec.dart` or `lib/src/editor/document.dart`
   - `flutter test test/markdown_codec_test.dart`
2. `lib/src/editor/editor_screen.dart` or `lib/src/editor/controller.dart`
   - `flutter test test/widget_test.dart`
3. Any Dart/Flutter source change
   - `flutter analyze`

If changes touch both UI and codec, run all of the above.

## Reporting Format

Report concise evidence:
- Command executed
- Pass/fail
- Key failing test or analyzer error (if any)
- Whether failure appears pre-existing or introduced by current change

## Failure Handling

1. Reproduce once to confirm.
2. Fix the smallest root cause first.
3. Re-run only affected command, then full relevant matrix.
4. Do not claim success without command evidence.

## Related References

- `AGENTS.md`
- `CLAUDE.md`
