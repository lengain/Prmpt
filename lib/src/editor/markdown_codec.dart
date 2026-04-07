import 'package:markdown/markdown.dart' as md;

import 'document.dart';

const String sampleMarkdown = r'''
# Prmpt WYSIWYG Markdown Editor

这是一个 **真正单视图** 的 Markdown 所见即所得编辑器示例，支持 **更明显的加粗示例**、*强调*、~~删除线~~、`行内代码`、[链接](https://flutter.dev) 和脚注引用 [^note]。

> 输入 Markdown 语法后，会在当前位置直接转成渲染样式，而不是显示单独的预览栏。

1. 输入 `# ` 自动转成标题块
2. 输入 `**粗体**` 自动转成加粗文本
3. 输入列表、表格、代码块后直接在当前区域内编辑

- [x] 所见即所得模式不分栏
- [x] 源码模式支持实时预览
- [x] 支持撤销 / 重做 / 复制 / 粘贴 / 清空 / 全选

| 能力 | 说明 |
| --- | --- |
| GFM | 遵循 GitHub Flavored Markdown |
| WYSIWYG | 编辑区就是渲染区 |

```dart
void main() {
  runApp(const PrmptApp());
}
```

[^note]: 这是一个脚注定义示例。
''';

enum InlineNodeType { text, strong, emphasis, strike, code, link, footnote }

class InlineNode {
  const InlineNode.text(this.text)
    : type = InlineNodeType.text,
      children = const <InlineNode>[],
      meta = '';

  const InlineNode.styled({
    required this.type,
    required this.children,
    this.meta = '',
    this.text = '',
  });

  final InlineNodeType type;
  final String text;
  final List<InlineNode> children;
  final String meta;
}

class MarkdownCodec {
  static MarkdownDocument importMarkdown(
    String markdown, {
    required String Function() nextId,
  }) {
    final normalized = sanitizePlainText(markdown).trimRight();
    final lines = normalized.isEmpty ? <String>[] : normalized.split('\n');
    final blocks = <MarkdownBlock>[];
    var index = 0;

    while (index < lines.length) {
      if (lines[index].trim().isEmpty) {
        index++;
        continue;
      }

      if (lines[index].trimRight().startsWith('```')) {
        final language = lines[index].trimRight().substring(3).trim();
        final buffer = <String>[];
        index++;
        while (index < lines.length &&
            !lines[index].trimRight().startsWith('```')) {
          buffer.add(lines[index]);
          index++;
        }
        if (index < lines.length) {
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.codeFence,
            language: language,
            code: buffer.join('\n'),
          ),
        );
        continue;
      }

      if (_isTableStart(lines, index)) {
        final rows = <List<StyledTextValue>>[];
        rows.add(
          _splitTableRow(lines[index]).map(parseInlineMarkdown).toList(),
        );
        index += 2;
        while (index < lines.length && _looksLikeTableRow(lines[index])) {
          rows.add(
            _splitTableRow(lines[index]).map(parseInlineMarkdown).toList(),
          );
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.table,
            rows: rows,
          ),
        );
        continue;
      }

      final footnoteMatch = RegExp(
        r'^\[\^([^\]]+)\]:\s*(.*)$',
      ).firstMatch(lines[index].trim());
      if (footnoteMatch != null) {
        final id = footnoteMatch.group(1) ?? '';
        final buffer = <String>[footnoteMatch.group(2) ?? ''];
        index++;
        while (index < lines.length &&
            (lines[index].startsWith('    ') ||
                lines[index].startsWith('\t'))) {
          buffer.add(lines[index].trimLeft());
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.footnote,
            footnoteId: id,
            text: parseInlineMarkdown(buffer.join('\n')),
          ),
        );
        continue;
      }

      final imageMatch = RegExp(
        r'^!\[(.*?)\]\((.*?)\)\s*$',
      ).firstMatch(lines[index].trim());
      if (imageMatch != null) {
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.image,
            alt: parseInlineMarkdown(imageMatch.group(1) ?? ''),
            url: imageMatch.group(2) ?? '',
          ),
        );
        index++;
        continue;
      }

      final headingMatch = RegExp(
        r'^(#{1,6})\s+(.*)$',
      ).firstMatch(lines[index].trimRight());
      if (headingMatch != null) {
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.heading,
            level: headingMatch.group(1)!.length,
            text: parseInlineMarkdown(headingMatch.group(2) ?? ''),
          ),
        );
        index++;
        continue;
      }

      if (_isTaskListLine(lines[index].trim())) {
        final items = <MarkdownListItem>[];
        while (index < lines.length && _isTaskListLine(lines[index].trim())) {
          final match = RegExp(
            r'^[-*+]\s+\[([ xX])\]\s+(.*)$',
          ).firstMatch(lines[index].trim());
          items.add(
            MarkdownListItem(
              checked: (match?.group(1) ?? '').toLowerCase() == 'x',
              content: parseInlineMarkdown(match?.group(2) ?? ''),
            ),
          );
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.taskList,
            items: items,
          ),
        );
        continue;
      }

      if (_isBulletListLine(lines[index].trim())) {
        final items = <MarkdownListItem>[];
        while (index < lines.length && _isBulletListLine(lines[index].trim())) {
          final match = RegExp(
            r'^[-*+]\s+(.*)$',
          ).firstMatch(lines[index].trim());
          items.add(
            MarkdownListItem(
              content: parseInlineMarkdown(match?.group(1) ?? ''),
            ),
          );
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.bulletList,
            items: items,
          ),
        );
        continue;
      }

      if (_isOrderedListLine(lines[index].trim())) {
        final items = <MarkdownListItem>[];
        while (index < lines.length &&
            _isOrderedListLine(lines[index].trim())) {
          final match = RegExp(
            r'^\d+\.\s+(.*)$',
          ).firstMatch(lines[index].trim());
          items.add(
            MarkdownListItem(
              content: parseInlineMarkdown(match?.group(1) ?? ''),
            ),
          );
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.orderedList,
            items: items,
          ),
        );
        continue;
      }

      if (_isQuoteLine(lines[index].trim())) {
        final buffer = <String>[];
        while (index < lines.length && _isQuoteLine(lines[index].trim())) {
          buffer.add(lines[index].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          index++;
        }
        blocks.add(
          MarkdownBlock(
            id: nextId(),
            type: MarkdownBlockType.quote,
            text: parseInlineMarkdown(buffer.join('\n')),
          ),
        );
        continue;
      }

      if (RegExp(r'^([-*_]){3,}\s*$').hasMatch(lines[index].trim())) {
        blocks.add(
          MarkdownBlock(id: nextId(), type: MarkdownBlockType.thematicBreak),
        );
        index++;
        continue;
      }

      final buffer = <String>[lines[index]];
      index++;
      while (index < lines.length &&
          lines[index].trim().isNotEmpty &&
          !_startsBlock(lines, index)) {
        buffer.add(lines[index]);
        index++;
      }
      blocks.add(
        MarkdownBlock(
          id: nextId(),
          type: MarkdownBlockType.paragraph,
          text: parseInlineMarkdown(buffer.join('\n')),
        ),
      );
    }

    if (blocks.isEmpty) {
      blocks.add(
        MarkdownBlock(
          id: nextId(),
          type: MarkdownBlockType.paragraph,
          text: const StyledTextValue(text: ''),
        ),
      );
    }

    return MarkdownDocument(blocks: blocks);
  }

  static MarkdownBlock buildParagraphLikeBlockFromInput({
    required String id,
    required MarkdownBlockType fallbackType,
    required int fallbackLevel,
    required StyledTextValue input,
  }) {
    final text = input.text;
    if (RegExp(r'^#{1,6}\s+').hasMatch(text)) {
      final match = RegExp(r'^(#{1,6})\s+').firstMatch(text)!;
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.heading,
        level: match.group(1)!.length,
        text: input.removePrefix(match.group(0)!.length),
      );
    }

    if (RegExp(r'^>\s?').hasMatch(text)) {
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.quote,
        text: parseInlineMarkdown(
          text
              .split('\n')
              .map((line) => line.replaceFirst(RegExp(r'^>\s?'), ''))
              .join('\n'),
        ),
      );
    }

    if (_looksLikeFencedCodeInput(text)) {
      final lines = text.split('\n');
      final language = lines.first.trim().substring(3).trim();
      final code = lines.sublist(1, lines.length - 1).join('\n');
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.codeFence,
        language: language,
        code: code,
      );
    }

    if (_looksLikeTableInput(text)) {
      final rows = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.table,
        rows: [
          _splitTableRow(rows.first).map(parseInlineMarkdown).toList(),
          ...rows
              .skip(2)
              .map(
                (row) => _splitTableRow(row).map(parseInlineMarkdown).toList(),
              ),
        ],
      );
    }

    final footnoteMatch = RegExp(r'^\[\^([^\]]+)\]:\s*(.*)$').firstMatch(text);
    if (footnoteMatch != null) {
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.footnote,
        footnoteId: footnoteMatch.group(1) ?? '',
        text: parseInlineMarkdown(footnoteMatch.group(2) ?? ''),
      );
    }

    if (_looksLikeTaskListInput(text)) {
      final items = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
            final match = RegExp(
              r'^[-*+]\s+\[([ xX])\]\s+(.*)$',
            ).firstMatch(line.trim());
            return MarkdownListItem(
              checked: (match?.group(1) ?? '').toLowerCase() == 'x',
              content: parseInlineMarkdown(match?.group(2) ?? ''),
            );
          })
          .toList(growable: false);
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.taskList,
        items: items.isEmpty
            ? <MarkdownListItem>[
                const MarkdownListItem(
                  checked: false,
                  content: StyledTextValue(text: ''),
                ),
              ]
            : items,
      );
    }

    if (_looksLikeOrderedListInput(text)) {
      final items = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty || RegExp(r'^\d+\.$').hasMatch(line.trim()))
          .map((line) {
            final match = RegExp(r'^(\d+\.)\s*(.*)$').firstMatch(line.trim());
            return MarkdownListItem(
              content: parseInlineMarkdown(match?.group(2) ?? ''),
            );
          })
          .toList(growable: false);
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.orderedList,
        items: items.isEmpty
            ? <MarkdownListItem>[
                const MarkdownListItem(content: StyledTextValue(text: '')),
              ]
            : items,
      );
    }

    if (_looksLikeBulletListInput(text)) {
      final items = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty || RegExp(r'^[-*+]$').hasMatch(line.trim()))
          .map((line) {
            final match = RegExp(r'^([-*+])\s*(.*)$').firstMatch(line.trim());
            return MarkdownListItem(
              content: parseInlineMarkdown(match?.group(2) ?? ''),
            );
          })
          .toList(growable: false);
      return MarkdownBlock(
        id: id,
        type: MarkdownBlockType.bulletList,
        items: items.isEmpty
            ? <MarkdownListItem>[
                const MarkdownListItem(content: StyledTextValue(text: '')),
              ]
            : items,
      );
    }

    if (RegExp(r'^([-*_]){3,}\s*$').hasMatch(text.trim())) {
      return MarkdownBlock(id: id, type: MarkdownBlockType.thematicBreak);
    }

    switch (fallbackType) {
      case MarkdownBlockType.heading:
        return MarkdownBlock(
          id: id,
          type: MarkdownBlockType.heading,
          level: fallbackLevel,
          text: input,
        );
      case MarkdownBlockType.quote:
        return MarkdownBlock(
          id: id,
          type: MarkdownBlockType.quote,
          text: input,
        );
      default:
        return MarkdownBlock(
          id: id,
          type: MarkdownBlockType.paragraph,
          text: input,
        );
    }
  }

  static StyledTextValue parseInlineMarkdown(String input) {
    if (input.isEmpty) {
      return const StyledTextValue(text: '');
    }

    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final footnoteRefs = RegExp(r'\[\^([^\]]+)\]')
        .allMatches(input)
        .map((match) => match.group(1) ?? '')
        .where((id) => id.isNotEmpty);
    for (final id in footnoteRefs) {
      document.footnoteReferences[id] = 0;
    }

    final nodes = document.parseInline(input);
    final buffer = StringBuffer();
    final marks = <InlineMark>[];

    void visit(List<md.Node> children) {
      for (final node in children) {
        if (node is md.Text) {
          buffer.write(node.text);
          continue;
        }

        if (node is! md.Element) {
          continue;
        }

        if (_isFootnoteReferenceElement(node)) {
          final footnoteId = _extractFootnoteId(node);
          final start = buffer.length;
          final label = '[$footnoteId]';
          buffer.write(label);
          final end = buffer.length;
          if (end > start) {
            marks.add(
              InlineMark(
                start: start,
                end: end,
                type: InlineMarkType.footnoteRef,
                data: footnoteId,
              ),
            );
          }
          continue;
        }

        switch (node.tag) {
          case 'strong':
            final start = buffer.length;
            visit(node.children ?? const <md.Node>[]);
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(start: start, end: end, type: InlineMarkType.bold),
              );
            }
          case 'em':
            final start = buffer.length;
            visit(node.children ?? const <md.Node>[]);
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(start: start, end: end, type: InlineMarkType.italic),
              );
            }
          case 'del':
            final start = buffer.length;
            visit(node.children ?? const <md.Node>[]);
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(start: start, end: end, type: InlineMarkType.strike),
              );
            }
          case 'code':
            final start = buffer.length;
            buffer.write(node.textContent);
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(start: start, end: end, type: InlineMarkType.code),
              );
            }
          case 'a':
            final start = buffer.length;
            visit(node.children ?? const <md.Node>[]);
            final end = buffer.length;
            if (end > start) {
              marks.add(
                InlineMark(
                  start: start,
                  end: end,
                  type: InlineMarkType.link,
                  data: node.attributes['href'] ?? '',
                ),
              );
            }
          case 'br':
            buffer.write('\n');
          default:
            visit(node.children ?? const <md.Node>[]);
        }
      }
    }

    visit(nodes);
    return StyledTextValue(text: buffer.toString(), marks: marks);
  }

  static String inlineToMarkdown(StyledTextValue value) {
    if (value.text.isEmpty) {
      return '';
    }

    final boundaries = <int>{0, value.text.length};
    for (final mark in value.marks) {
      boundaries
        ..add(mark.start)
        ..add(mark.end);
    }
    final sorted = boundaries.toList()..sort();
    final buffer = StringBuffer();

    for (var i = 0; i < sorted.length - 1; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (end <= start) {
        continue;
      }

      final segmentText = value.text.substring(start, end);
      final activeMarks = value.marks
          .where((mark) => mark.start <= start && mark.end >= end)
          .toList(growable: false);
      buffer.write(_wrapSegment(segmentText, activeMarks));
    }

    return buffer.toString();
  }

  static String exportMarkdown(MarkdownDocument document) {
    final buffer = StringBuffer();
    for (final block in document.blocks) {
      _writeBlockMarkdown(buffer, block);
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  static String exportBlockMarkdown(MarkdownBlock block) {
    final buffer = StringBuffer();
    _writeBlockMarkdown(buffer, block);
    return buffer.toString().trimRight();
  }

  static String exportHtml(MarkdownDocument document) {
    return md.markdownToHtml(
      exportMarkdown(document),
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
  }

  static MarkdownBlock buildBlockFromMarkdownInput({
    required String id,
    required MarkdownBlock fallbackBlock,
    required String input,
  }) {
    final imported = importMarkdown(input, nextId: () => id).blocks;
    final block = imported.isEmpty ? fallbackBlock : imported.first;
    return block.copyWith(id: id);
  }

  static List<InlineNode> parseInlineNodes(String text) {
    if (text.isEmpty) {
      return const <InlineNode>[];
    }

    final patterns = <_InlinePattern>[
      _InlinePattern(
        type: InlineNodeType.link,
        expression: RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      ),
      _InlinePattern(
        type: InlineNodeType.code,
        expression: RegExp(r'`([^`]+)`'),
      ),
      _InlinePattern(
        type: InlineNodeType.strong,
        expression: RegExp(r'\*\*([^*]+)\*\*'),
      ),
      _InlinePattern(
        type: InlineNodeType.strike,
        expression: RegExp(r'~~([^~]+)~~'),
      ),
      _InlinePattern(
        type: InlineNodeType.emphasis,
        expression: RegExp(r'\*([^*\n]+)\*'),
      ),
      _InlinePattern(
        type: InlineNodeType.emphasis,
        expression: RegExp(r'_([^_\n]+)_'),
      ),
      _InlinePattern(
        type: InlineNodeType.footnote,
        expression: RegExp(r'\[\^([^\]]+)\]'),
      ),
    ];

    final nodes = <InlineNode>[];
    var cursor = 0;
    while (cursor < text.length) {
      _InlineMatch? next;
      for (final pattern in patterns) {
        final match = pattern.expression.firstMatch(text.substring(cursor));
        if (match == null) {
          continue;
        }
        final candidate = _InlineMatch(
          pattern: pattern,
          start: cursor + match.start,
          end: cursor + match.end,
          match: match,
        );
        if (next == null || candidate.start < next.start) {
          next = candidate;
        }
      }

      if (next == null) {
        nodes.add(InlineNode.text(text.substring(cursor)));
        break;
      }

      if (next.start > cursor) {
        nodes.add(InlineNode.text(text.substring(cursor, next.start)));
      }

      switch (next.pattern.type) {
        case InlineNodeType.link:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.link,
              meta: next.match.group(2) ?? '',
              children: parseInlineNodes(next.match.group(1) ?? ''),
            ),
          );
        case InlineNodeType.code:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.code,
              children: const <InlineNode>[],
              text: next.match.group(1) ?? '',
            ),
          );
        case InlineNodeType.strong:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.strong,
              children: parseInlineNodes(next.match.group(1) ?? ''),
            ),
          );
        case InlineNodeType.emphasis:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.emphasis,
              children: parseInlineNodes(next.match.group(1) ?? ''),
            ),
          );
        case InlineNodeType.strike:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.strike,
              children: parseInlineNodes(next.match.group(1) ?? ''),
            ),
          );
        case InlineNodeType.footnote:
          nodes.add(
            InlineNode.styled(
              type: InlineNodeType.footnote,
              children: const <InlineNode>[],
              text: next.match.group(1) ?? '',
            ),
          );
        case InlineNodeType.text:
          nodes.add(InlineNode.text(next.match.group(0) ?? ''));
      }

      cursor = next.end;
    }

    return nodes;
  }

  static String sanitizePlainText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  }

  static String templateForType(MarkdownBlockType type) {
    switch (type) {
      case MarkdownBlockType.heading:
        return '## 新标题';
      case MarkdownBlockType.paragraph:
        return '新的段落支持 **粗体**、**更明显的加粗示例**、*强调*、~~删除线~~ 和 `代码`。';
      case MarkdownBlockType.quote:
        return '> 这是一个引用块示例。';
      case MarkdownBlockType.bulletList:
        return '- 列表项一\n- 列表项二';
      case MarkdownBlockType.orderedList:
        return '1. 第一步\n2. 第二步\n3. 第三步';
      case MarkdownBlockType.taskList:
        return '- [x] 已完成\n- [ ] 待处理';
      case MarkdownBlockType.codeFence:
        return '```dart\nvoid main() {}\n```';
      case MarkdownBlockType.table:
        return '| 列 1 | 列 2 |\n| --- | --- |\n| 值 1 | 值 2 |';
      case MarkdownBlockType.image:
        return '![示例图片](https://picsum.photos/960/540)';
      case MarkdownBlockType.footnote:
        return '[^demo]: 这是一个脚注示例。';
      case MarkdownBlockType.thematicBreak:
        return '---';
    }
  }

  static bool _startsBlock(List<String> lines, int index) {
    final current = lines[index].trim();
    return current.startsWith('```') ||
        _isTableStart(lines, index) ||
        current.startsWith('#') ||
        _isTaskListLine(current) ||
        _isBulletListLine(current) ||
        _isOrderedListLine(current) ||
        _isQuoteLine(current) ||
        current.startsWith('![') ||
        current.startsWith('[^') ||
        RegExp(r'^([-*_]){3,}\s*$').hasMatch(current);
  }

  static bool _isTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    return _looksLikeTableRow(lines[index]) &&
        _isTableSeparator(lines[index + 1]);
  }

  static bool _looksLikeTableRow(String line) {
    return line.contains('|');
  }

  static bool _isTableSeparator(String line) {
    return RegExp(
      r'^\s*\|?(?:\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?\s*$',
    ).hasMatch(line);
  }

  static List<String> _splitTableRow(String line) {
    var working = line.trim();
    if (working.startsWith('|')) {
      working = working.substring(1);
    }
    if (working.endsWith('|')) {
      working = working.substring(0, working.length - 1);
    }
    return working
        .split('|')
        .map((cell) => cell.trim())
        .toList(growable: false);
  }

  static bool _isTaskListLine(String line) {
    return RegExp(r'^[-*+]\s+\[[ xX]\]\s+').hasMatch(line);
  }

  static bool _isBulletListLine(String line) {
    return !_isTaskListLine(line) && RegExp(r'^[-*+]\s+').hasMatch(line);
  }

  static bool _isOrderedListLine(String line) {
    return RegExp(r'^\d+\.\s+').hasMatch(line);
  }

  static bool _isQuoteLine(String line) {
    return line.startsWith('>');
  }

  static bool _looksLikeFencedCodeInput(String text) {
    final lines = text.split('\n');
    return lines.length >= 2 &&
        lines.first.trim().startsWith('```') &&
        lines.last.trim() == '```';
  }

  static bool _looksLikeTableInput(String text) {
    final lines = text.split('\n');
    return lines.length >= 2 &&
        _looksLikeTableRow(lines.first) &&
        _isTableSeparator(lines[1]);
  }

  static bool _looksLikeTaskListInput(String text) {
    final lines = text.split('\n');
    return lines.isNotEmpty &&
        lines.every(
          (line) => line.trim().isEmpty || _isTaskListLine(line.trim()),
        );
  }

  static bool _looksLikeBulletListInput(String text) {
    final lines = text.split('\n');
    return lines.isNotEmpty &&
        lines.every(
          (line) =>
              line.trim().isEmpty ||
              _isBulletListLine(line.trim()) ||
              RegExp(r'^[-*+]$').hasMatch(line.trim()),
        );
  }

  static bool _looksLikeOrderedListInput(String text) {
    final lines = text.split('\n');
    return lines.isNotEmpty &&
        lines.every(
          (line) =>
              line.trim().isEmpty ||
              _isOrderedListLine(line.trim()) ||
              RegExp(r'^\d+\.$').hasMatch(line.trim()),
        );
  }

  static String _wrapSegment(String segment, List<InlineMark> marks) {
    if (segment.isEmpty) {
      return segment;
    }

    final codeMark = marks
        .where((mark) => mark.type == InlineMarkType.code)
        .firstOrNull;
    if (codeMark != null) {
      return '`$segment`';
    }

    final footnoteMark = marks
        .where((mark) => mark.type == InlineMarkType.footnoteRef)
        .firstOrNull;
    if (footnoteMark != null) {
      return '[^${footnoteMark.data}]';
    }

    var result = segment;
    if (marks.any((mark) => mark.type == InlineMarkType.link)) {
      final link = marks.firstWhere((mark) => mark.type == InlineMarkType.link);
      result = '[$result](${link.data})';
    }
    if (marks.any((mark) => mark.type == InlineMarkType.bold)) {
      result = '**$result**';
    }
    if (marks.any((mark) => mark.type == InlineMarkType.italic)) {
      result = '*$result*';
    }
    if (marks.any((mark) => mark.type == InlineMarkType.strike)) {
      result = '~~$result~~';
    }
    return result;
  }

  static String _tableRow(List<StyledTextValue> row) {
    return '| ${row.map(inlineToMarkdown).join(' | ')} |';
  }

  static void _writeBlockMarkdown(StringBuffer buffer, MarkdownBlock block) {
    switch (block.type) {
      case MarkdownBlockType.heading:
        buffer.writeln('${'#' * block.level} ${inlineToMarkdown(block.text)}');
      case MarkdownBlockType.paragraph:
        buffer.writeln(inlineToMarkdown(block.text));
      case MarkdownBlockType.quote:
        for (final line in inlineToMarkdown(block.text).split('\n')) {
          buffer.writeln('> $line');
        }
      case MarkdownBlockType.bulletList:
        for (final item in block.items) {
          buffer.writeln('- ${inlineToMarkdown(item.content)}');
        }
      case MarkdownBlockType.orderedList:
        for (var i = 0; i < block.items.length; i++) {
          buffer.writeln(
            '${i + 1}. ${inlineToMarkdown(block.items[i].content)}',
          );
        }
      case MarkdownBlockType.taskList:
        for (final item in block.items) {
          final check = item.checked ? 'x' : ' ';
          buffer.writeln('- [$check] ${inlineToMarkdown(item.content)}');
        }
      case MarkdownBlockType.codeFence:
        buffer.writeln('```${block.language}'.trimRight());
        buffer.writeln(block.code);
        buffer.writeln('```');
      case MarkdownBlockType.table:
        if (block.rows.isNotEmpty) {
          buffer.writeln(_tableRow(block.rows.first));
          buffer.writeln(
            _tableRow(
              block.rows.first
                  .map((cell) => const StyledTextValue(text: '---'))
                  .toList(),
            ),
          );
          for (final row in block.rows.skip(1)) {
            buffer.writeln(_tableRow(row));
          }
        }
      case MarkdownBlockType.image:
        buffer.writeln('![${inlineToMarkdown(block.alt)}](${block.url})');
      case MarkdownBlockType.footnote:
        buffer.writeln(
          '[^${block.footnoteId}]: ${inlineToMarkdown(block.text)}',
        );
      case MarkdownBlockType.thematicBreak:
        buffer.writeln('---');
    }
  }

  static bool _isFootnoteReferenceElement(md.Element element) {
    return element.tag == 'sup' &&
        element.attributes['class'] == 'footnote-ref';
  }

  static String _extractFootnoteId(md.Element element) {
    final link = element.children?.whereType<md.Element>().firstOrNull;
    final href = link?.attributes['href'] ?? '';
    if (href.startsWith('#fn-')) {
      return Uri.decodeComponent(href.substring(4));
    }
    return link?.textContent ?? element.textContent;
  }
}

class _InlinePattern {
  const _InlinePattern({required this.type, required this.expression});

  final InlineNodeType type;
  final RegExp expression;
}

class _InlineMatch {
  const _InlineMatch({
    required this.pattern,
    required this.start,
    required this.end,
    required this.match,
  });

  final _InlinePattern pattern;
  final int start;
  final int end;
  final Match match;
}
