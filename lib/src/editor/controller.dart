import 'package:flutter/foundation.dart';

import 'document.dart';
import 'markdown_codec.dart';

class MarkdownEditorController extends ChangeNotifier {
  MarkdownEditorController({String initialMarkdown = sampleMarkdown})
    : _document = const MarkdownDocument(blocks: <MarkdownBlock>[]),
      _rawMarkdown = '' {
    replaceSource(initialMarkdown, recordHistory: false);
  }

  MarkdownDocument _document;
  String _rawMarkdown;
  final List<MarkdownDocument> _undoStack = <MarkdownDocument>[];
  final List<MarkdownDocument> _redoStack = <MarkdownDocument>[];
  int _idSeed = 0;
  bool _liveEditing = false;

  MarkdownDocument get document => _document;
  List<MarkdownBlock> get blocks => _document.blocks;
  String get markdown => _rawMarkdown;
  String get html => MarkdownCodec.exportHtml(_document);
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get blockCount => _document.blockCount;
  int get headingCount => _document.headingCount;
  int get sourceLength => _document.sourceLength;

  void loadSample() {
    replaceSource(sampleMarkdown);
  }

  void clearDocument() {
    endLiveEditing();
    _recordHistory();
    _document = MarkdownCodec.importMarkdown('', nextId: _nextId);
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void replaceSource(String source, {bool recordHistory = true}) {
    endLiveEditing();
    if (recordHistory) {
      _recordHistory();
    }
    _document = MarkdownCodec.importMarkdown(source, nextId: _nextId);
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) {
      return;
    }
    _redoStack.add(_document.clone());
    _document = _undoStack.removeLast();
    _syncMarkdown();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) {
      return;
    }
    _undoStack.add(_document.clone());
    _document = _redoStack.removeLast();
    _syncMarkdown();
    notifyListeners();
  }

  void addBlock(MarkdownBlockType type, {String? afterBlockId}) {
    endLiveEditing();
    _recordHistory();
    final blocks = _document.blocks.toList(growable: true);
    final insertIndex = afterBlockId == null
        ? blocks.length
        : blocks.indexWhere((block) => block.id == afterBlockId) + 1;
    final template = MarkdownCodec.importMarkdown(
      MarkdownCodec.templateForType(type),
      nextId: _nextId,
    ).blocks.first;
    blocks.insert(
      insertIndex.clamp(0, blocks.length),
      template.copyWith(id: _nextId()),
    );
    _document = MarkdownDocument(
      blocks: List<MarkdownBlock>.unmodifiable(blocks),
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void duplicateBlock(String blockId) {
    final blocks = _document.blocks.toList(growable: true);
    final index = blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) {
      return;
    }
    endLiveEditing();
    _recordHistory();
    blocks.insert(index + 1, blocks[index].clone().copyWith(id: _nextId()));
    _document = MarkdownDocument(
      blocks: List<MarkdownBlock>.unmodifiable(blocks),
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void deleteBlock(String blockId) {
    endLiveEditing();
    _recordHistory();
    final remaining = _document.blocks
        .where((block) => block.id != blockId)
        .toList(growable: false);
    _document = MarkdownDocument(
      blocks: remaining.isEmpty
          ? MarkdownCodec.importMarkdown('', nextId: _nextId).blocks
          : remaining,
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void moveBlock(String blockId, int delta) {
    final blocks = _document.blocks.toList(growable: true);
    final index = blocks.indexWhere((block) => block.id == blockId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= blocks.length) {
      return;
    }
    endLiveEditing();
    _recordHistory();
    final block = blocks.removeAt(index);
    blocks.insert(target, block);
    _document = MarkdownDocument(
      blocks: List<MarkdownBlock>.unmodifiable(blocks),
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void reorderBlock(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) {
      return;
    }
    endLiveEditing();
    final blocks = _document.blocks.toList(growable: true);
    if (oldIndex < 0 || oldIndex >= blocks.length) {
      return;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= blocks.length) {
      return;
    }
    _recordHistory();
    final block = blocks.removeAt(oldIndex);
    blocks.insert(targetIndex, block);
    _document = MarkdownDocument(
      blocks: List<MarkdownBlock>.unmodifiable(blocks),
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void beginLiveEditing() {
    if (_liveEditing) {
      return;
    }
    _recordHistory();
    _redoStack.clear();
    _liveEditing = true;
  }

  void endLiveEditing() {
    _liveEditing = false;
  }

  void updateParagraphLikeBlock(
    String blockId,
    StyledTextValue value, {
    bool recordHistory = true,
  }) {
    _replaceBlock(blockId, (block) {
      return MarkdownCodec.buildParagraphLikeBlockFromInput(
        id: block.id,
        fallbackType: block.type,
        fallbackLevel: block.level,
        input: value,
      );
    }, recordHistory: recordHistory);
  }

  void updateBlockMarkdown(
    String blockId,
    String markdown, {
    bool recordHistory = true,
  }) {
    _replaceBlock(blockId, (block) {
      return MarkdownCodec.buildBlockFromMarkdownInput(
        id: block.id,
        fallbackBlock: block,
        input: markdown,
      );
    }, recordHistory: recordHistory);
  }

  void updateListItem(
    String blockId,
    int itemIndex,
    StyledTextValue value, {
    bool recordHistory = true,
  }) {
    _replaceBlock(blockId, (block) {
      final items = block.items.toList(growable: true);
      items[itemIndex] = items[itemIndex].copyWith(content: value);
      return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
    }, recordHistory: recordHistory);
  }

  void toggleTaskItem(String blockId, int itemIndex, bool checked) {
    _replaceBlock(blockId, (block) {
      final items = block.items.toList(growable: true);
      items[itemIndex] = items[itemIndex].copyWith(checked: checked);
      return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
    });
  }

  void addListItem(String blockId) {
    _replaceBlock(blockId, (block) {
      final items = block.items.toList(growable: true)
        ..add(const MarkdownListItem(content: StyledTextValue(text: '')));
      return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
    });
  }

  void insertListItemAfter(String blockId, int itemIndex) {
    _replaceBlock(blockId, (block) {
      final items = block.items.toList(growable: true);
      items.insert(
        (itemIndex + 1).clamp(0, items.length),
        const MarkdownListItem(content: StyledTextValue(text: '')),
      );
      return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
    });
  }

  void removeListItem(String blockId, int itemIndex) {
    _replaceBlock(blockId, (block) {
      final items = block.items.toList(growable: true);
      if (items.length == 1) {
        items[0] = const MarkdownListItem(content: StyledTextValue(text: ''));
      } else {
        items.removeAt(itemIndex);
      }
      return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
    });
  }

  void updateCodeLanguage(
    String blockId,
    String language, {
    bool recordHistory = true,
  }) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(language: language),
      recordHistory: recordHistory,
    );
  }

  void updateCode(String blockId, String code, {bool recordHistory = true}) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(code: code),
      recordHistory: recordHistory,
    );
  }

  void updateTableCell(
    String blockId,
    int row,
    int column,
    StyledTextValue value, {
    bool recordHistory = true,
  }) {
    _replaceBlock(blockId, (block) {
      final rows = block.rows
          .map(
            (current) =>
                current.map((cell) => cell.clone()).toList(growable: true),
          )
          .toList(growable: true);
      rows[row][column] = value;
      return block.copyWith(
        rows: rows
            .map((r) => List<StyledTextValue>.unmodifiable(r))
            .toList(growable: false),
      );
    }, recordHistory: recordHistory);
  }

  void addTableRow(String blockId) {
    _replaceBlock(blockId, (block) {
      final columnCount = block.rows.isEmpty ? 2 : block.rows.first.length;
      final rows =
          block.rows
              .map(
                (row) => row.map((cell) => cell.clone()).toList(growable: true),
              )
              .toList(growable: true)
            ..add(
              List<StyledTextValue>.filled(
                columnCount,
                const StyledTextValue(text: ''),
              ),
            );
      return block.copyWith(
        rows: rows
            .map((row) => List<StyledTextValue>.unmodifiable(row))
            .toList(growable: false),
      );
    });
  }

  void addTableColumn(String blockId) {
    _replaceBlock(blockId, (block) {
      final rows = block.rows
          .map(
            (row) =>
                row.map((cell) => cell.clone()).toList(growable: true)
                  ..add(const StyledTextValue(text: '')),
          )
          .toList(growable: true);
      return block.copyWith(
        rows: rows
            .map((row) => List<StyledTextValue>.unmodifiable(row))
            .toList(growable: false),
      );
    });
  }

  void removeTableRow(String blockId) {
    _replaceBlock(blockId, (block) {
      final rows = block.rows
          .map((row) => row.map((cell) => cell.clone()).toList(growable: true))
          .toList(growable: true);
      if (rows.length > 1) {
        rows.removeLast();
      }
      return block.copyWith(
        rows: rows
            .map((row) => List<StyledTextValue>.unmodifiable(row))
            .toList(growable: false),
      );
    });
  }

  void removeTableColumn(String blockId) {
    _replaceBlock(blockId, (block) {
      if (block.rows.isEmpty || block.rows.first.length <= 1) {
        return block;
      }
      final rows = block.rows
          .map(
            (row) =>
                row.map((cell) => cell.clone()).toList(growable: true)
                  ..removeLast(),
          )
          .toList(growable: true);
      return block.copyWith(
        rows: rows
            .map((row) => List<StyledTextValue>.unmodifiable(row))
            .toList(growable: false),
      );
    });
  }

  void updateImageAlt(
    String blockId,
    StyledTextValue value, {
    bool recordHistory = true,
  }) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(alt: value),
      recordHistory: recordHistory,
    );
  }

  void updateImageUrl(String blockId, String url, {bool recordHistory = true}) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(url: url),
      recordHistory: recordHistory,
    );
  }

  void updateFootnoteId(
    String blockId,
    String id, {
    bool recordHistory = true,
  }) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(footnoteId: id),
      recordHistory: recordHistory,
    );
  }

  void updateFootnoteText(
    String blockId,
    StyledTextValue value, {
    bool recordHistory = true,
  }) {
    _replaceBlock(
      blockId,
      (block) => block.copyWith(text: value),
      recordHistory: recordHistory,
    );
  }

  /// Splits a paragraph-like block at [cursorOffset], producing two blocks.
  /// The current block keeps the text before [cursorOffset]; a new paragraph
  /// block is inserted after it with the text after [cursorOffset].
  void splitBlock(String blockId, int cursorOffset) {
    endLiveEditing();
    _recordHistory();
    final block = _document.blocks
        .where((b) => b.id == blockId)
        .firstOrNull;
    if (block == null) return;

    StyledTextValue beforeValue;
    StyledTextValue afterValue;

    switch (block.type) {
      case MarkdownBlockType.heading:
      case MarkdownBlockType.paragraph:
      case MarkdownBlockType.quote:
      case MarkdownBlockType.footnote:
        final text = block.text.text;
        beforeValue = block.text.slice(0, cursorOffset.clamp(0, text.length));
        afterValue = block.text.slice(cursorOffset.clamp(0, text.length), text.length);
      case MarkdownBlockType.bulletList:
      case MarkdownBlockType.orderedList:
      case MarkdownBlockType.taskList:
        final item = block.items.firstOrNull;
        if (item == null) {
          addBlock(MarkdownBlockType.paragraph, afterBlockId: blockId);
          return;
        }
        final content = item.content.text;
        beforeValue = item.content.slice(0, cursorOffset.clamp(0, content.length));
        afterValue = item.content.slice(cursorOffset.clamp(0, content.length), content.length);
      case _:
        addBlock(MarkdownBlockType.paragraph, afterBlockId: blockId);
        return;
    }

    _replaceBlock(blockId, (b) => _setParagraphLikeText(b, beforeValue));
    addBlock(MarkdownBlockType.paragraph, afterBlockId: blockId);
    final newBlock = _document.blocks
        .where((b) => b.id != blockId)
        .lastOrNull;
    if (newBlock != null) {
      _replaceBlock(newBlock.id, (b) => _setParagraphLikeText(b, afterValue));
    }
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  /// Merges the block after [blockId] into this block.
  /// Returns the cursor offset for the merged content.
  ({String blockId, int cursorOffset})? mergeBlockWithNext(String blockId) {
    endLiveEditing();
    final blocks = _document.blocks.toList(growable: true);
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index < 0 || index >= blocks.length - 1) return null;

    final current = blocks[index];
    final next = blocks[index + 1];

    _recordHistory();

    final mergedText = _mergeTextValues(_primaryTextValue(current), _primaryTextValue(next));
    _replaceBlock(blockId, (b) => _setParagraphLikeText(b, mergedText));

    final remaining = blocks.where((b) => b.id != next.id).toList();
    _document = MarkdownDocument(blocks: List<MarkdownBlock>.unmodifiable(remaining));

    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
    return (blockId: blockId, cursorOffset: mergedText.text.length);
  }

  /// Merges [blockId] into the previous block and deletes [blockId].
  /// Returns the previous block ID and cursor offset.
  ({String blockId, int cursorOffset})? mergeBlockWithPrevious(String blockId) {
    endLiveEditing();
    final blocks = _document.blocks.toList(growable: true);
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index <= 0) return null;

    final prev = blocks[index - 1];
    final current = blocks[index];

    _recordHistory();

    final mergedText = _mergeTextValues(_primaryTextValue(prev), _primaryTextValue(current));
    _replaceBlock(prev.id, (b) => _setParagraphLikeText(b, mergedText));

    final remaining = blocks.where((b) => b.id != blockId).toList();
    _document = MarkdownDocument(blocks: List<MarkdownBlock>.unmodifiable(remaining));

    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
    return (blockId: prev.id, cursorOffset: _primaryTextValue(prev).text.length);
  }

  /// Exits the list at [blockId] by converting to a paragraph.
  void exitList(String blockId) {
    convertBlock(blockId, MarkdownBlockType.paragraph);
  }

  void convertBlock(String blockId, MarkdownBlockType type) {
    _replaceBlock(blockId, (block) => _convertBlock(block, type));
  }

  void convertBlockToHeading(String blockId, int level) {
    _replaceBlock(blockId, (block) {
      return MarkdownBlock(
        id: block.id,
        type: MarkdownBlockType.heading,
        level: level.clamp(1, 6),
        text: _primaryTextValue(block),
      );
    });
  }

  void applyBlockExample(String blockId) {
    final block = _document.blocks
        .where((candidate) => candidate.id == blockId)
        .firstOrNull;
    if (block == null) {
      return;
    }
    final imported = MarkdownCodec.importMarkdown(
      MarkdownCodec.templateForType(block.type),
      nextId: _nextId,
    ).blocks.first;
    _replaceBlock(blockId, (current) => imported.copyWith(id: current.id));
  }

  void _replaceBlock(
    String blockId,
    MarkdownBlock Function(MarkdownBlock block) transform, {
    bool recordHistory = true,
  }) {
    if (recordHistory) {
      endLiveEditing();
      _recordHistory();
    }
    _document = MarkdownDocument(
      blocks: _document.blocks
          .map((block) => block.id == blockId ? transform(block) : block)
          .toList(growable: false),
    );
    _syncMarkdown();
    _redoStack.clear();
    notifyListeners();
  }

  void _recordHistory() {
    _undoStack.add(_document.clone());
    if (_undoStack.length > 120) {
      _undoStack.removeAt(0);
    }
  }

  void _syncMarkdown() {
    _rawMarkdown = MarkdownCodec.exportMarkdown(_document);
  }

  MarkdownBlock _setParagraphLikeText(MarkdownBlock block, StyledTextValue text) {
    switch (block.type) {
      case MarkdownBlockType.heading:
      case MarkdownBlockType.paragraph:
      case MarkdownBlockType.quote:
      case MarkdownBlockType.footnote:
        return block.copyWith(text: text);
      case MarkdownBlockType.bulletList:
      case MarkdownBlockType.orderedList:
      case MarkdownBlockType.taskList:
        if (block.items.isEmpty) return block;
        final items = block.items.toList(growable: true);
        items[0] = items[0].copyWith(content: text);
        return block.copyWith(items: List<MarkdownListItem>.unmodifiable(items));
      default:
        return block;
    }
  }

  StyledTextValue _mergeTextValues(StyledTextValue a, StyledTextValue b) {
    if (a.text.isEmpty) return b.clone();
    if (b.text.isEmpty) return a.clone();
    final mergedText = '${a.text}\n${b.text}';
    // Combine marks: shift b's marks by a.text.length.
    final shiftedMarks = b.marks.map((m) => m.copyWith(
      start: m.start + a.text.length + 1,
      end: m.end + a.text.length + 1,
    )).toList();
    return StyledTextValue(
      text: mergedText,
      marks: <InlineMark>[...a.marks, ...shiftedMarks],
    );
  }

  MarkdownBlock _convertBlock(MarkdownBlock block, MarkdownBlockType type) {
    final primaryText = _primaryTextValue(block);
    switch (type) {
      case MarkdownBlockType.heading:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.heading,
          level: block.type == MarkdownBlockType.heading ? block.level : 1,
          text: primaryText,
        );
      case MarkdownBlockType.paragraph:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.paragraph,
          text: primaryText,
        );
      case MarkdownBlockType.quote:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.quote,
          text: primaryText,
        );
      case MarkdownBlockType.bulletList:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.bulletList,
          items: <MarkdownListItem>[MarkdownListItem(content: primaryText)],
        );
      case MarkdownBlockType.orderedList:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.orderedList,
          items: <MarkdownListItem>[MarkdownListItem(content: primaryText)],
        );
      case MarkdownBlockType.taskList:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.taskList,
          items: <MarkdownListItem>[
            MarkdownListItem(
              content: primaryText,
              checked: block.type == MarkdownBlockType.taskList
                  ? block.items.firstOrNull?.checked ?? false
                  : false,
            ),
          ],
        );
      case MarkdownBlockType.codeFence:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.codeFence,
          language: block.type == MarkdownBlockType.codeFence
              ? block.language
              : '',
          code: block.type == MarkdownBlockType.codeFence
              ? block.code
              : MarkdownCodec.inlineToMarkdown(primaryText),
        );
      case MarkdownBlockType.table:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.table,
          rows: <List<StyledTextValue>>[
            <StyledTextValue>[
              primaryText.isEmpty
                  ? const StyledTextValue(text: '列 1')
                  : primaryText,
              const StyledTextValue(text: '列 2'),
            ],
            const <StyledTextValue>[
              StyledTextValue(text: ''),
              StyledTextValue(text: ''),
            ],
          ],
        );
      case MarkdownBlockType.image:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.image,
          alt: block.type == MarkdownBlockType.image ? block.alt : primaryText,
          url: block.type == MarkdownBlockType.image ? block.url : '',
        );
      case MarkdownBlockType.footnote:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.footnote,
          footnoteId: block.type == MarkdownBlockType.footnote
              ? block.footnoteId
              : 'note',
          text: primaryText,
        );
      case MarkdownBlockType.thematicBreak:
        return MarkdownBlock(
          id: block.id,
          type: MarkdownBlockType.thematicBreak,
        );
    }
  }

  StyledTextValue _primaryTextValue(MarkdownBlock block) {
    switch (block.type) {
      case MarkdownBlockType.heading:
      case MarkdownBlockType.paragraph:
      case MarkdownBlockType.quote:
      case MarkdownBlockType.footnote:
        return block.text.clone();
      case MarkdownBlockType.bulletList:
      case MarkdownBlockType.orderedList:
      case MarkdownBlockType.taskList:
        return block.items.firstOrNull?.content.clone() ??
            const StyledTextValue(text: '');
      case MarkdownBlockType.codeFence:
        return StyledTextValue(text: block.code);
      case MarkdownBlockType.table:
        return block.rows.firstOrNull?.firstOrNull?.clone() ??
            const StyledTextValue(text: '');
      case MarkdownBlockType.image:
        return block.alt.clone();
      case MarkdownBlockType.thematicBreak:
        return const StyledTextValue(text: '');
    }
  }

  String _nextId() {
    _idSeed += 1;
    return 'block-$_idSeed';
  }
}
