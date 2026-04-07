enum MarkdownBlockType {
  heading('标题'),
  paragraph('段落'),
  quote('引用'),
  bulletList('无序列表'),
  orderedList('有序列表'),
  taskList('任务列表'),
  codeFence('代码块'),
  table('表格'),
  image('图片'),
  footnote('脚注'),
  thematicBreak('分隔线');

  const MarkdownBlockType(this.label);

  final String label;
}

enum InlineMarkType { bold, italic, strike, code, link, footnoteRef }

class InlineMark {
  const InlineMark({
    required this.start,
    required this.end,
    required this.type,
    this.data = '',
  });

  final int start;
  final int end;
  final InlineMarkType type;
  final String data;

  InlineMark copyWith({
    int? start,
    int? end,
    InlineMarkType? type,
    String? data,
  }) {
    return InlineMark(
      start: start ?? this.start,
      end: end ?? this.end,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }
}

class StyledTextValue {
  const StyledTextValue({
    required this.text,
    this.marks = const <InlineMark>[],
  });

  final String text;
  final List<InlineMark> marks;

  bool get isEmpty => text.isEmpty;

  StyledTextValue copyWith({String? text, List<InlineMark>? marks}) {
    return StyledTextValue(text: text ?? this.text, marks: marks ?? this.marks);
  }

  StyledTextValue clone() {
    return StyledTextValue(
      text: text,
      marks: marks.map((mark) => mark.copyWith()).toList(growable: false),
    );
  }

  StyledTextValue slice(int start, int end) {
    final clampedStart = start.clamp(0, text.length);
    final clampedEnd = end.clamp(clampedStart, text.length);
    final slicedText = text.substring(clampedStart, clampedEnd);
    final slicedMarks = <InlineMark>[];

    for (final mark in marks) {
      final overlapStart = mark.start.clamp(clampedStart, clampedEnd);
      final overlapEnd = mark.end.clamp(clampedStart, clampedEnd);
      if (overlapEnd <= overlapStart) {
        continue;
      }
      slicedMarks.add(
        InlineMark(
          start: overlapStart - clampedStart,
          end: overlapEnd - clampedStart,
          type: mark.type,
          data: mark.data,
        ),
      );
    }

    return StyledTextValue(text: slicedText, marks: slicedMarks);
  }

  StyledTextValue removePrefix(int length) {
    return slice(length, text.length);
  }

  StyledTextValue removeRange(int start, int end) {
    final left = slice(0, start);
    final right = slice(end, text.length);
    final mergedMarks = <InlineMark>[
      ...left.marks,
      ...right.marks.map(
        (mark) => mark.copyWith(
          start: mark.start + left.text.length,
          end: mark.end + left.text.length,
        ),
      ),
    ];
    return StyledTextValue(text: left.text + right.text, marks: mergedMarks);
  }
}

class MarkdownListItem {
  const MarkdownListItem({required this.content, this.checked = false});

  final StyledTextValue content;
  final bool checked;

  MarkdownListItem copyWith({StyledTextValue? content, bool? checked}) {
    return MarkdownListItem(
      content: content ?? this.content,
      checked: checked ?? this.checked,
    );
  }
}

class MarkdownBlock {
  const MarkdownBlock({
    required this.id,
    required this.type,
    this.text = const StyledTextValue(text: ''),
    this.level = 1,
    this.items = const <MarkdownListItem>[],
    this.rows = const <List<StyledTextValue>>[],
    this.language = '',
    this.code = '',
    this.url = '',
    this.alt = const StyledTextValue(text: ''),
    this.footnoteId = '',
  });

  final String id;
  final MarkdownBlockType type;
  final StyledTextValue text;
  final int level;
  final List<MarkdownListItem> items;
  final List<List<StyledTextValue>> rows;
  final String language;
  final String code;
  final String url;
  final StyledTextValue alt;
  final String footnoteId;

  MarkdownBlock copyWith({
    String? id,
    MarkdownBlockType? type,
    StyledTextValue? text,
    int? level,
    List<MarkdownListItem>? items,
    List<List<StyledTextValue>>? rows,
    String? language,
    String? code,
    String? url,
    StyledTextValue? alt,
    String? footnoteId,
  }) {
    return MarkdownBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      level: level ?? this.level,
      items: items ?? this.items,
      rows: rows ?? this.rows,
      language: language ?? this.language,
      code: code ?? this.code,
      url: url ?? this.url,
      alt: alt ?? this.alt,
      footnoteId: footnoteId ?? this.footnoteId,
    );
  }

  MarkdownBlock clone() {
    return MarkdownBlock(
      id: id,
      type: type,
      text: text.clone(),
      level: level,
      items: items
          .map((item) => item.copyWith(content: item.content.clone()))
          .toList(growable: false),
      rows: rows
          .map((row) => row.map((cell) => cell.clone()).toList(growable: false))
          .toList(growable: false),
      language: language,
      code: code,
      url: url,
      alt: alt.clone(),
      footnoteId: footnoteId,
    );
  }
}

class MarkdownDocument {
  const MarkdownDocument({required this.blocks});

  final List<MarkdownBlock> blocks;

  MarkdownDocument clone() {
    return MarkdownDocument(
      blocks: blocks.map((block) => block.clone()).toList(growable: false),
    );
  }

  int get blockCount => blocks.length;

  int get sourceLength {
    var total = 0;
    for (final block in blocks) {
      total += block.text.text.length;
      total += block.code.length;
      total += block.url.length;
      total += block.alt.text.length;
      total += block.footnoteId.length;
      for (final item in block.items) {
        total += item.content.text.length;
      }
      for (final row in block.rows) {
        for (final cell in row) {
          total += cell.text.length;
        }
      }
    }
    return total;
  }

  int get headingCount =>
      blocks.where((block) => block.type == MarkdownBlockType.heading).length;
}
