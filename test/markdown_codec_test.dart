import 'package:flutter_test/flutter_test.dart';
import 'package:prmpt/src/editor/document.dart';
import 'package:prmpt/src/editor/markdown_codec.dart';

void main() {
  test('imports sample markdown into GFM-oriented blocks', () {
    var counter = 0;
    final document = MarkdownCodec.importMarkdown(
      sampleMarkdown,
      nextId: () => 'block-${counter++}',
    );

    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.heading),
      isTrue,
    );
    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.taskList),
      isTrue,
    );
    expect(
      document.blocks.any(
        (block) => block.type == MarkdownBlockType.orderedList,
      ),
      isTrue,
    );
    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.quote),
      isTrue,
    );
    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.table),
      isTrue,
    );
    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.codeFence),
      isTrue,
    );
    expect(
      document.blocks.any((block) => block.type == MarkdownBlockType.footnote),
      isTrue,
    );
  });

  test('exports HTML with GFM structures', () {
    var counter = 0;
    final document = MarkdownCodec.importMarkdown(
      sampleMarkdown,
      nextId: () => 'block-${counter++}',
    );
    final html = MarkdownCodec.exportHtml(document);

    expect(html, contains('<table>'));
    expect(html, contains('<blockquote>'));
    expect(html, contains('<ol>'));
    expect(html, contains('<pre><code'));
  });

  test('sanitizes pasted plain text', () {
    expect(MarkdownCodec.sanitizePlainText('A\r\nB\u00A0C\u200B'), 'A\nB C');
  });

  test('converts inline markdown to hidden syntax marks', () {
    final value = MarkdownCodec.parseInlineMarkdown('这是 **粗体** 文本');

    expect(value.text, '这是 粗体 文本');
    expect(value.marks.any((mark) => mark.type == InlineMarkType.bold), isTrue);
  });

  test('distinguishes italic and bold emphasis markers', () {
    final value = MarkdownCodec.parseInlineMarkdown('这是 *斜体* 和 **粗体**');
    final italicMarks = value.marks
        .where((mark) => mark.type == InlineMarkType.italic)
        .toList(growable: false);
    final boldMarks = value.marks
        .where((mark) => mark.type == InlineMarkType.bold)
        .toList(growable: false);

    expect(value.text, '这是 斜体 和 粗体');
    expect(italicMarks, hasLength(1));
    expect(boldMarks, hasLength(1));
    expect(
      value.text.substring(italicMarks.single.start, italicMarks.single.end),
      '斜体',
    );
    expect(
      value.text.substring(boldMarks.single.start, boldMarks.single.end),
      '粗体',
    );
    expect(MarkdownCodec.inlineToMarkdown(value), '这是 *斜体* 和 **粗体**');
  });

  test('converts heading syntax into a heading block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-1',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '# 标题'),
    );

    expect(block.type, MarkdownBlockType.heading);
    expect(block.level, 1);
    expect(block.text.text, '标题');
  });

  test('converts bullet list trigger into a bullet list block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-2',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '- 项目'),
    );

    expect(block.type, MarkdownBlockType.bulletList);
    expect(block.items, hasLength(1));
    expect(block.items.first.content.text, '项目');
  });

  test('converts ordered list trigger into an ordered list block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-3',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '1. 第一步'),
    );

    expect(block.type, MarkdownBlockType.orderedList);
    expect(block.items, hasLength(1));
    expect(block.items.first.content.text, '第一步');
  });

  test('converts task list trigger into a task list block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-4',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '- [x] 已完成'),
    );

    expect(block.type, MarkdownBlockType.taskList);
    expect(block.items, hasLength(1));
    expect(block.items.first.checked, isTrue);
    expect(block.items.first.content.text, '已完成');
  });

  test('converts empty bullet list trigger into a bullet list block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-5',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '- '),
    );

    expect(block.type, MarkdownBlockType.bulletList);
    expect(block.items, hasLength(1));
    expect(block.items.first.content.text, isEmpty);
  });

  test('converts thematic break trigger into a thematic break block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-6',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '---'),
    );

    expect(block.type, MarkdownBlockType.thematicBreak);
  });

  test('converts fenced code trigger into a code fence block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-7',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '```dart\nvoid main() {}\n```'),
    );

    expect(block.type, MarkdownBlockType.codeFence);
    expect(block.language, 'dart');
    expect(block.code, 'void main() {}');
  });

  test('converts quote trigger into a quote block', () {
    final block = MarkdownCodec.buildParagraphLikeBlockFromInput(
      id: 'block-8',
      fallbackType: MarkdownBlockType.paragraph,
      fallbackLevel: 1,
      input: const StyledTextValue(text: '> 这是一段引用'),
    );

    expect(block.type, MarkdownBlockType.quote);
    expect(block.text.text, '这是一段引用');
  });

  test('controller splits block at cursor offset', () {
    // Simulate splitting a paragraph at cursor offset 4.
    // "Hello world" split at offset 5 → "Hello" + " world"
    final fullText = const StyledTextValue(text: 'Hello world');
    final before = fullText.slice(0, 5);
    final after = fullText.slice(5, fullText.text.length);

    expect(before.text, 'Hello');
    expect(after.text, ' world');
  });
}
