import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'controller.dart';
import 'document.dart';
import 'markdown_codec.dart';

enum EditorMode {
  wysiwyg('所见即所得'),
  source('源码编辑');

  const EditorMode(this.label);

  final String label;
}

enum EditorFrameMode {
  fixed('固定高度'),
  max('最大高度'),
  fullscreen('全屏编辑');

  const EditorFrameMode(this.label);

  final String label;
}

class PrmptApp extends StatelessWidget {
  const PrmptApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        surface: const Color(0xFFF8F5EE),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F1E8),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prmpt Markdown Editor',
      theme: baseTheme,
      home: const MarkdownEditorScreen(),
    );
  }
}

class MarkdownEditorScreen extends StatefulWidget {
  const MarkdownEditorScreen({super.key});

  @override
  State<MarkdownEditorScreen> createState() => _MarkdownEditorScreenState();
}

class _MarkdownEditorScreenState extends State<MarkdownEditorScreen> {
  late final MarkdownEditorController _controller;
  late final TextEditingController _sourceController;
  late final FocusNode _sourceFocusNode;

  EditorMode _mode = EditorMode.wysiwyg;
  EditorFrameMode _frameMode = EditorFrameMode.max;
  TextEditingController? _activeTextController;
  FocusNode? _activeFocusNode;
  bool _syncingSourceController = false;
  final Map<String, GlobalKey<MarkdownBlockEditorState>> _blockEditorKeys =
      <String, GlobalKey<MarkdownBlockEditorState>>{};

  @override
  void initState() {
    super.initState();
    _controller = MarkdownEditorController()..addListener(_syncSourceFromState);
    _sourceController = TextEditingController(text: _controller.markdown)
      ..addListener(_handleSourceChanged);
    _sourceFocusNode = FocusNode()
      ..addListener(() {
        if (_sourceFocusNode.hasFocus) {
          _registerActiveEditor(_sourceController, _sourceFocusNode);
        }
      });
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSourceFromState);
    _controller.dispose();
    _sourceController
      ..removeListener(_handleSourceChanged)
      ..dispose();
    _sourceFocusNode.dispose();
    super.dispose();
  }

  void _syncSourceFromState() {
    if (_syncingSourceController ||
        _sourceController.text == _controller.markdown) {
      return;
    }

    _syncingSourceController = true;
    final selection = _sourceController.selection;
    final offset = selection.isValid
        ? selection.baseOffset.clamp(0, _controller.markdown.length)
        : _controller.markdown.length;
    _sourceController.value = TextEditingValue(
      text: _controller.markdown,
      selection: TextSelection.collapsed(offset: offset),
    );
    _syncingSourceController = false;
  }

  void _handleSourceChanged() {
    if (_syncingSourceController) {
      return;
    }
    _registerActiveEditor(_sourceController, _sourceFocusNode);
    _controller.replaceSource(_sourceController.text);
  }

  void _registerActiveEditor(
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    _activeTextController = controller;
    _activeFocusNode = focusNode;
  }

  Future<void> _copySelectionOrDocument() async {
    final active = _activeTextController;
    final focus = _activeFocusNode;
    if (active != null && focus?.hasFocus == true) {
      final selection = active.selection;
      final text = selection.isValid && !selection.isCollapsed
          ? selection.textInside(active.text)
          : active.text;
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage('已复制当前内容');
      return;
    }

    await Clipboard.setData(ClipboardData(text: _controller.markdown));
    _showMessage('已复制整篇 Markdown');
  }

  Future<void> _pasteSanitized() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final sanitized = MarkdownCodec.sanitizePlainText(data?.text ?? '');
    if (sanitized.isEmpty) {
      _showMessage('剪贴板里没有可用文本');
      return;
    }

    final active = _activeTextController;
    final focus = _activeFocusNode;
    if (active != null && focus?.hasFocus == true) {
      final selection = active.selection.isValid
          ? active.selection
          : TextSelection.collapsed(offset: active.text.length);
      final nextText =
          selection.textBefore(active.text) +
          sanitized +
          selection.textAfter(active.text);
      active.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(
          offset: selection.start + sanitized.length,
        ),
      );
      _showMessage('已按纯文本粘贴');
      return;
    }

    if (_mode == EditorMode.source) {
      _sourceFocusNode.requestFocus();
      _sourceController.value = TextEditingValue(
        text: _sourceController.text + sanitized,
        selection: TextSelection.collapsed(
          offset: _sourceController.text.length + sanitized.length,
        ),
      );
      _showMessage('已追加到源码编辑区');
      return;
    }

    _controller.addBlock(MarkdownBlockType.paragraph);
    final block = _controller.blocks.last;
    _controller.updateParagraphLikeBlock(
      block.id,
      StyledTextValue(text: sanitized),
    );
    _showMessage('已作为新段落粘贴');
  }

  void _selectAll() {
    final active = _activeTextController;
    final focus = _activeFocusNode;
    if (active != null && focus?.hasFocus == true) {
      active.selection = TextSelection(
        baseOffset: 0,
        extentOffset: active.text.length,
      );
      return;
    }

    if (_mode == EditorMode.source) {
      _sourceFocusNode.requestFocus();
      _sourceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _sourceController.text.length,
      );
      return;
    }

    _showMessage('请先聚焦到一个可编辑区域');
  }

  void _clearDocument() {
    _controller.clearDocument();
    _showMessage('文档已清空');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleLinkTap(String text, String? href, String title) {
    if (href == null || href.isEmpty) {
      _showMessage('链接地址为空');
      return;
    }
    Clipboard.setData(ClipboardData(text: href));
    _showMessage('已复制链接: $href');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(
                _frameMode == EditorFrameMode.fullscreen ? 12 : 20,
              ),
              child: Column(
                children: [
                  if (_frameMode != EditorFrameMode.fullscreen) ...[
                    _Header(controller: _controller),
                    const SizedBox(height: 16),
                  ],
                  _Toolbar(
                    mode: _mode,
                    frameMode: _frameMode,
                    canUndo: _controller.canUndo,
                    canRedo: _controller.canRedo,
                    onModeChanged: (value) => setState(() => _mode = value),
                    onFrameModeChanged: (value) =>
                        setState(() => _frameMode = value),
                    onLoadSample: _controller.loadSample,
                    onUndo: _controller.canUndo ? _controller.undo : null,
                    onRedo: _controller.canRedo ? _controller.redo : null,
                    onCopy: _copySelectionOrDocument,
                    onPaste: _pasteSanitized,
                    onSelectAll: _selectAll,
                    onClear: _clearDocument,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildFrame(
                          constraints: constraints,
                          child: _mode == EditorMode.wysiwyg
                              ? _buildWysiwygSurface()
                              : _buildSourceSurface(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFrame({
    required BoxConstraints constraints,
    required Widget child,
  }) {
    final frame = Container(
      width: constraints.maxWidth,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(
          _frameMode == EditorFrameMode.fullscreen ? 22 : 28,
        ),
        border: Border.all(color: const Color(0xFFE5DCCF)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 28,
            offset: Offset(0, 10),
            color: Color(0x1217212B),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    switch (_frameMode) {
      case EditorFrameMode.fixed:
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: math.min(720, constraints.maxHeight),
            child: frame,
          ),
        );
      case EditorFrameMode.max:
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: math.min(880, constraints.maxHeight),
            child: frame,
          ),
        );
      case EditorFrameMode.fullscreen:
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: frame,
        );
    }
  }

  Widget _buildWysiwygSurface() {
    return Column(
      children: [
        Expanded(
          child: MarkdownWidget(
            controller: _controller,
            onActivateEditor: _registerActiveEditor,
            onTapLink: _handleLinkTap,
            blockEditorKeys: _blockEditorKeys,
            onRequestFocus: _requestBlockFocus,
          ),
        ),
        const SizedBox(height: 12),
        _AddBlockBar(onAdd: (type) => _controller.addBlock(type)),
      ],
    );
  }

  void _requestBlockFocus(String blockId, {int? cursorOffset}) {
    final state = _blockEditorKeys[blockId]?.currentState;
    if (state != null) {
      state.requestFocus(cursorOffset: cursorOffset);
    }
  }

  Widget _buildSourceSurface() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 980;
        final editor = _SourcePane(
          controller: _sourceController,
          focusNode: _sourceFocusNode,
          onActivateEditor: _registerActiveEditor,
        );
        final preview = _SourcePreview(
          markdown: _sourceController.text,
          onTapLink: _handleLinkTap,
        );

        if (split) {
          return Row(
            children: [
              Expanded(child: editor),
              const VerticalDivider(width: 1),
              Expanded(child: preview),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 6, child: editor),
            const Divider(height: 1),
            Expanded(flex: 5, child: preview),
          ],
        );
      },
    );
  }
}

class MarkdownWidget extends StatefulWidget {
  const MarkdownWidget({
    super.key,
    required this.controller,
    required this.onActivateEditor,
    required this.onTapLink,
    required this.blockEditorKeys,
    required this.onRequestFocus,
  });

  final MarkdownEditorController controller;
  final void Function(TextEditingController, FocusNode) onActivateEditor;
  final void Function(String text, String? href, String title) onTapLink;
  final Map<String, GlobalKey<MarkdownBlockEditorState>> blockEditorKeys;
  final void Function(String blockId, {int? cursorOffset}) onRequestFocus;

  @override
  State<MarkdownWidget> createState() => _MarkdownWidgetState();
}

class _MarkdownWidgetState extends State<MarkdownWidget> {
  @override
  void didUpdateWidget(covariant MarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkPendingFocus();
  }

  @override
  void initState() {
    super.initState();
    _checkPendingFocus();
  }

  void _checkPendingFocus() {
    final pendingId = widget.controller.pendingFocusBlockId;
    if (pendingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final offset = widget.controller.pendingFocusCursorOffset;
        widget.onRequestFocus(pendingId, cursorOffset: offset);
        widget.controller.clearPendingFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      buildDefaultDragHandles: false,
      itemCount: widget.controller.blocks.length,
      onReorder: widget.controller.reorderBlock,
      itemBuilder: (context, index) {
        final block = widget.controller.blocks[index];
        final key = widget.blockEditorKeys.putIfAbsent(
          block.id,
          () => GlobalKey<MarkdownBlockEditorState>(),
        );
        return Padding(
          key: ValueKey(block.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: _MarkdownBlockEditor(
            key: key,
            index: index,
            block: block,
            controller: widget.controller,
            onActivateEditor: widget.onActivateEditor,
            onTapLink: widget.onTapLink,
            onRequestFocus: widget.onRequestFocus,
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F766E).withValues(alpha: 0.18),
            const Color(0xFFE8C98D).withValues(alpha: 0.30),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prmpt True WYSIWYG Markdown Editor',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '默认进入单视图所见即所得模式。整个编辑区是一个连续的 MarkdownWidget，像 Notion 一样直接在内容里编辑；输入标题、粗体、列表、表格和代码块语法时会在当前位置实时渲染，不再拆成多张块卡片。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.55,
                    color: const Color(0xFF30404A),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(label: 'Blocks', value: '${controller.blockCount}'),
              _MetricChip(
                label: 'Headings',
                value: '${controller.headingCount}',
              ),
              _MetricChip(label: 'Chars', value: '${controller.sourceLength}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.mode,
    required this.frameMode,
    required this.canUndo,
    required this.canRedo,
    required this.onModeChanged,
    required this.onFrameModeChanged,
    required this.onLoadSample,
    required this.onUndo,
    required this.onRedo,
    required this.onCopy,
    required this.onPaste,
    required this.onSelectAll,
    required this.onClear,
  });

  final EditorMode mode;
  final EditorFrameMode frameMode;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<EditorMode> onModeChanged;
  final ValueChanged<EditorFrameMode> onFrameModeChanged;
  final VoidCallback onLoadSample;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final Future<void> Function() onCopy;
  final Future<void> Function() onPaste;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SegmentedButton<EditorMode>(
          showSelectedIcon: false,
          segments: EditorMode.values
              .map(
                (mode) => ButtonSegment<EditorMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
              )
              .toList(growable: false),
          selected: <EditorMode>{mode},
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        SegmentedButton<EditorFrameMode>(
          showSelectedIcon: false,
          segments: EditorFrameMode.values
              .map(
                (mode) => ButtonSegment<EditorFrameMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
              )
              .toList(growable: false),
          selected: <EditorFrameMode>{frameMode},
          onSelectionChanged: (selection) =>
              onFrameModeChanged(selection.first),
        ),
        FilledButton.tonalIcon(
          onPressed: onLoadSample,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('加载示例'),
        ),
        FilledButton.tonalIcon(
          onPressed: onUndo,
          icon: const Icon(Icons.undo_rounded),
          label: const Text('撤销'),
        ),
        FilledButton.tonalIcon(
          onPressed: onRedo,
          icon: const Icon(Icons.redo_rounded),
          label: const Text('重做'),
        ),
        OutlinedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('复制'),
        ),
        OutlinedButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste_rounded),
          label: const Text('粘贴'),
        ),
        OutlinedButton.icon(
          onPressed: onSelectAll,
          icon: const Icon(Icons.select_all_rounded),
          label: const Text('全选'),
        ),
        OutlinedButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.layers_clear_rounded),
          label: const Text('清空'),
        ),
      ],
    );
  }
}

class _MarkdownBlockEditor extends StatefulWidget {
  const _MarkdownBlockEditor({
    super.key,
    required this.index,
    required this.block,
    required this.controller,
    required this.onActivateEditor,
    required this.onTapLink,
    required this.onRequestFocus,
  });

  final int index;
  final MarkdownBlock block;
  final MarkdownEditorController controller;
  final void Function(TextEditingController, FocusNode) onActivateEditor;
  final void Function(String text, String? href, String title) onTapLink;
  final void Function(String blockId, {int? cursorOffset}) onRequestFocus;

  @override
  State<_MarkdownBlockEditor> createState() => MarkdownBlockEditorState();
}

class MarkdownBlockEditorState extends State<_MarkdownBlockEditor> {
  bool _focused = false;
  String? _rawText; // 存储原始 Markdown 文本（包含标记）
  final GlobalKey<_RichMarkdownFieldState> _richFieldKey =
      GlobalKey<_RichMarkdownFieldState>();

  void requestFocus({int? cursorOffset}) {
    _richFieldKey.currentState?.requestFocus(cursorOffset: cursorOffset);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEditor(context),
      ],
    );
  }

  void _onEditingStarted() {
    widget.controller.beginLiveEditing();
    setState(() => _focused = true);
  }

  void _onEditingEnded() {
    widget.controller.endLiveEditing();
    // 获取当前文本
    final currentText = _rawText ?? widget.block.text.text;
    
    // 先检测格式标记
    final trigger = _detectBlockTrigger(currentText);
    String pureText = currentText;
    
    if (trigger != null) {
      // 如果检测到格式标记，使用去掉标记后的文本
      pureText = trigger.strippedText;
      // 应用块类型转换
      _handleBlockTrigger(trigger);
    } else {
      // 对于 heading/quote 等已有类型的块，去掉前缀
      final prefix = _getBlockPrefix();
      if (prefix.isNotEmpty && currentText.startsWith(prefix)) {
        pureText = currentText.substring(prefix.length);
      }
    }
    
    // 保存纯文本
    widget.controller.updateParagraphLikeBlock(
      widget.block.id,
      StyledTextValue(text: pureText),
      recordHistory: false,
    );
    
    _rawText = null;
    setState(() => _focused = false);
  }

  /// 获取编辑时显示的文本（带格式标记前缀）
  StyledTextValue _getEditingValue() {
    final text = widget.block.text.text;
    final prefix = _getBlockPrefix();
    if (prefix.isEmpty || text.startsWith(prefix)) {
      return widget.block.text;
    }
    return StyledTextValue(
      text: prefix + text,
      marks: _shiftMarks(widget.block.text.marks, prefix.length),
    );
  }

  /// 获取当前块类型的 Markdown 前缀
  String _getBlockPrefix() {
    switch (widget.block.type) {
      case MarkdownBlockType.heading:
        return '#' * widget.block.level + ' ';
      case MarkdownBlockType.quote:
        return '> ';
      default:
        return '';
    }
  }

  /// 将 marks 的偏移量向后移动指定长度
  List<InlineMark> _shiftMarks(List<InlineMark> marks, int shift) {
    return marks.map((mark) => InlineMark(
      start: mark.start + shift,
      end: mark.end + shift,
      type: mark.type,
      data: mark.data,
    )).toList(growable: false);
  }

  /// 去掉文本中的格式前缀，返回纯文本值
  StyledTextValue _stripPrefix(String text) {
    final prefix = _getBlockPrefix();
    if (prefix.isEmpty || !text.startsWith(prefix)) {
      return StyledTextValue(text: text);
    }
    return StyledTextValue(
      text: text.substring(prefix.length),
      marks: _shiftMarks(
        widget.block.text.marks.where((m) => m.start >= prefix.length).toList(),
        -prefix.length,
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    // 编辑时显示带前缀的文本，预览时显示纯文本
    final displayValue = _focused ? _getEditingValue() : widget.block.text;

    switch (widget.block.type) {
      case MarkdownBlockType.heading:
        return _RichMarkdownField(
          key: _richFieldKey,
          value: displayValue,
          style: _blockStyle(context, widget.block),
          hintText: '输入标题内容，或在段落中使用 # 创建标题',
          onActivateEditor: widget.onActivateEditor,
          onEditingStarted: _onEditingStarted,
          onEditingEnded: _onEditingEnded,
          onChanged: (value) {
            // 编辑时保存原始文本（含前缀）
            _rawText = value.text;
            widget.controller.updateParagraphLikeBlock(
              widget.block.id,
              value,
              recordHistory: false,
            );
          },
          onSlashCommandSelected: _handleSlashCommand,
          onBlockTriggerDetected: null, // 编辑时不再自动触发块类型转换
          onSplitBlock: (offset) {
            // 分割时去掉前缀
            final currentText = _rawText ?? widget.block.text.text;
            final pureValue = _stripPrefix(currentText);
            widget.controller.updateParagraphLikeBlock(
              widget.block.id,
              pureValue,
              recordHistory: false,
            );
            widget.controller.splitBlock(widget.block.id, offset);
          },
          onBackspaceOnEmpty: _deleteCurrentBlockIfPossible,
          onMergeWithPrevious: _mergeWithPreviousBlock,
          onFocusPreviousBlock: _focusPreviousBlock,
          onFocusNextBlock: _focusNextBlock,
          slashCommands: _slashCommands,
        );
      case MarkdownBlockType.paragraph:
        return _RichMarkdownField(
          key: _richFieldKey,
          value: widget.block.text,
          style: _blockStyle(context, widget.block),
          hintText: '直接输入 Markdown，语法会在当前位置自动渲染',
          onActivateEditor: widget.onActivateEditor,
          onEditingStarted: _onEditingStarted,
          onEditingEnded: _onEditingEnded,
          onChanged: (value) {
            _rawText = value.text;
            widget.controller.updateParagraphLikeBlock(
              widget.block.id,
              value,
              recordHistory: false,
            );
          },
          onSlashCommandSelected: _handleSlashCommand,
          onBlockTriggerDetected: null, // 段落编辑时也禁用自动触发，失去焦点后统一处理
          onSplitBlock: (offset) =>
              widget.controller.splitBlock(widget.block.id, offset),
          onBackspaceOnEmpty: _deleteCurrentBlockIfPossible,
          onMergeWithPrevious: _mergeWithPreviousBlock,
          onFocusPreviousBlock: _focusPreviousBlock,
          onFocusNextBlock: _focusNextBlock,
          slashCommands: _slashCommands,
        );
      case MarkdownBlockType.quote:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F5EE),
            border: Border(
              left: BorderSide(color: Color(0xFF0F766E), width: 4),
            ),
          ),
          child: _RichMarkdownField(
            key: _richFieldKey,
            value: displayValue,
            style: _blockStyle(context, widget.block),
            hintText: '输入引用内容',
            onActivateEditor: widget.onActivateEditor,
            onEditingStarted: _onEditingStarted,
            onEditingEnded: _onEditingEnded,
            onChanged: (value) {
              _rawText = value.text;
              widget.controller.updateParagraphLikeBlock(
                widget.block.id,
                value,
                recordHistory: false,
              );
            },
            onSlashCommandSelected: _handleSlashCommand,
            onBlockTriggerDetected: null,
            onSplitBlock: (offset) {
              final currentText = _rawText ?? widget.block.text.text;
              final pureValue = _stripPrefix(currentText);
              widget.controller.updateParagraphLikeBlock(
                widget.block.id,
                pureValue,
                recordHistory: false,
              );
              widget.controller.splitBlock(widget.block.id, offset);
            },
            onBackspaceOnEmpty: _deleteCurrentBlockIfPossible,
            onMergeWithPrevious: _mergeWithPreviousBlock,
            onFocusPreviousBlock: _focusPreviousBlock,
            onFocusNextBlock: _focusNextBlock,
            slashCommands: _slashCommands,
          ),
        );
      case MarkdownBlockType.bulletList:
      case MarkdownBlockType.orderedList:
      case MarkdownBlockType.taskList:
        return Column(
          children: [
            for (var i = 0; i < widget.block.items.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 42,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: widget.block.type == MarkdownBlockType.taskList
                          ? Checkbox(
                              value: widget.block.items[i].checked,
                              onChanged: (value) =>
                                  widget.controller.toggleTaskItem(
                                    widget.block.id,
                                    i,
                                    value ?? false,
                                  ),
                            )
                          : Text(
                              widget.block.type == MarkdownBlockType.orderedList
                                  ? '${i + 1}.'
                                  : '•',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                  Expanded(
                    child: _RichMarkdownField(
                      value: widget.block.items[i].content,
                      style:
                          Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(height: 1.65) ??
                          const TextStyle(fontSize: 16, height: 1.65),
                      hintText: '列表项',
                      onActivateEditor: widget.onActivateEditor,
                      onEditingStarted: _onEditingStarted,
                      onEditingEnded: _onEditingEnded,
                      onChanged: (value) => widget.controller.updateListItem(
                        widget.block.id,
                        i,
                        value,
                        recordHistory: false,
                      ),
                      onEnterPressed: () => widget.controller
                          .insertListItemAfter(widget.block.id, i),
                      onBackspaceOnEmpty: () =>
                          _handleEmptyListItemBackspace(i),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        widget.controller.removeListItem(widget.block.id, i),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                ],
              ),
              if (i != widget.block.items.length - 1)
                const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.controller.addListItem(widget.block.id),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新增列表项'),
              ),
            ),
          ],
        );
      case MarkdownBlockType.codeFence:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: _PlainMultilineField(
                  text: widget.block.language,
                  hintText: '语言',
                  style: const TextStyle(
                    color: Color(0xFFF9FAFB),
                    fontWeight: FontWeight.w700,
                  ),
                  onActivateEditor: widget.onActivateEditor,
                  onEditingStarted: _onEditingStarted,
                  onEditingEnded: _onEditingEnded,
                  onChanged: (value) => widget.controller.updateCodeLanguage(
                    widget.block.id,
                    value,
                    recordHistory: false,
                  ),
                  dense: true,
                  fillColor: const Color(0xFF0F172A),
                  borderColor: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 12),
              _PlainMultilineField(
                text: widget.block.code,
                hintText: '代码内容',
                style: const TextStyle(
                  color: Color(0xFFF9FAFB),
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
                fillColor: const Color(0xFF0F172A),
                borderColor: const Color(0xFF334155),
                onActivateEditor: widget.onActivateEditor,
                onEditingStarted: _onEditingStarted,
                onEditingEnded: _onEditingEnded,
                onChanged: (value) => widget.controller.updateCode(
                  widget.block.id,
                  value,
                  recordHistory: false,
                ),
              ),
            ],
          ),
        );
      case MarkdownBlockType.table:
        final columnCount = widget.block.rows.isNotEmpty
            ? widget.block.rows.first.length
            : 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                border: TableBorder.all(color: const Color(0xFFD8CCBC)),
                columnWidths: {
                  for (var i = 0; i < columnCount; i++)
                    i: const FixedColumnWidth(180),
                },
                children: [
                  for (var row = 0; row < widget.block.rows.length; row++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: row == 0
                            ? const Color(0xFFEFF7F5)
                            : const Color(0xFFFFFCF8),
                      ),
                      children: [
                        for (
                          var column = 0;
                          column < widget.block.rows[row].length;
                          column++
                        )
                          Container(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: _RichMarkdownField(
                              value: widget.block.rows[row][column],
                              style:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    fontWeight: row == 0
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    height: 1.55,
                                  ) ??
                                  const TextStyle(fontSize: 14),
                              hintText: row == 0 ? '表头' : '单元格',
                              onActivateEditor: widget.onActivateEditor,
                              onEditingStarted: _onEditingStarted,
                              onEditingEnded: _onEditingEnded,
                              onChanged: (value) =>
                                  widget.controller.updateTableCell(
                                    widget.block.id,
                                    row,
                                    column,
                                    value,
                                    recordHistory: false,
                                  ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.controller.addTableRow(widget.block.id),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加行'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.controller.removeTableRow(widget.block.id),
                  icon: const Icon(Icons.horizontal_rule_rounded),
                  label: const Text('减少行'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.controller.addTableColumn(widget.block.id),
                  icon: const Icon(Icons.view_column_rounded),
                  label: const Text('添加列'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.controller.removeTableColumn(widget.block.id),
                  icon: const Icon(Icons.remove_rounded),
                  label: const Text('减少列'),
                ),
              ],
            ),
          ],
        );
      case MarkdownBlockType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RichMarkdownField(
              value: widget.block.alt,
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ) ??
                  const TextStyle(fontStyle: FontStyle.italic),
              hintText: '图片说明',
              onActivateEditor: widget.onActivateEditor,
              onEditingStarted: _onEditingStarted,
              onEditingEnded: _onEditingEnded,
              onChanged: (value) => widget.controller.updateImageAlt(
                widget.block.id,
                value,
                recordHistory: false,
              ),
            ),
            const SizedBox(height: 12),
            _PlainMultilineField(
              text: widget.block.url,
              hintText: '图片 URL',
              style:
                  Theme.of(context).textTheme.bodyMedium ??
                  const TextStyle(fontSize: 14),
              onActivateEditor: widget.onActivateEditor,
              onEditingStarted: _onEditingStarted,
              onEditingEnded: _onEditingEnded,
              onChanged: (value) => widget.controller.updateImageUrl(
                widget.block.id,
                value,
                recordHistory: false,
              ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.block.url.trim().isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFEAE5DD),
                        child: Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      )
                    : Image.network(
                        widget.block.url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const ColoredBox(
                            color: Color(0xFFEAE5DD),
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      case MarkdownBlockType.footnote:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: _PlainMultilineField(
                text: widget.block.footnoteId,
                hintText: '脚注 ID',
                style:
                    Theme.of(context).textTheme.bodyMedium ??
                    const TextStyle(fontSize: 14),
                onActivateEditor: widget.onActivateEditor,
                onEditingStarted: _onEditingStarted,
                onEditingEnded: _onEditingEnded,
                onChanged: (value) => widget.controller.updateFootnoteId(
                  widget.block.id,
                  value,
                  recordHistory: false,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RichMarkdownField(
                value: widget.block.text,
                style:
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.65) ??
                    const TextStyle(fontSize: 16, height: 1.65),
                hintText: '脚注内容',
                onActivateEditor: widget.onActivateEditor,
                onEditingStarted: _onEditingStarted,
                onEditingEnded: _onEditingEnded,
                onChanged: (value) => widget.controller.updateFootnoteText(
                  widget.block.id,
                  value,
                  recordHistory: false,
                ),
                onEnterPressed: () => widget.controller.addBlock(
                  MarkdownBlockType.paragraph,
                  afterBlockId: widget.block.id,
                ),
              ),
            ),
          ],
        );
      case MarkdownBlockType.thematicBreak:
        return const Divider(height: 32, thickness: 2);
    }
  }

  List<_SlashCommandOption> get _slashCommands => <_SlashCommandOption>[
    _SlashCommandOption.text(
      label: 'Text',
      keywords: 'paragraph text 段落 正文',
      icon: Icons.notes_rounded,
    ),
    _SlashCommandOption.heading(
      label: 'Heading 1',
      keywords: 'h1 title 标题 一级',
      icon: Icons.looks_one_rounded,
      level: 1,
    ),
    _SlashCommandOption.heading(
      label: 'Heading 2',
      keywords: 'h2 title 标题 二级',
      icon: Icons.looks_two_rounded,
      level: 2,
    ),
    _SlashCommandOption.heading(
      label: 'Heading 3',
      keywords: 'h3 title 标题 三级',
      icon: Icons.looks_3_rounded,
      level: 3,
    ),
    _SlashCommandOption.text(
      label: 'Bullet List',
      keywords: 'list bullet 无序 列表',
      icon: Icons.format_list_bulleted_rounded,
      type: MarkdownBlockType.bulletList,
    ),
    _SlashCommandOption.text(
      label: 'Numbered List',
      keywords: 'list ordered numbered 有序 列表',
      icon: Icons.format_list_numbered_rounded,
      type: MarkdownBlockType.orderedList,
    ),
    _SlashCommandOption.text(
      label: 'To-do List',
      keywords: 'todo task checkbox 待办 任务',
      icon: Icons.check_box_outlined,
      type: MarkdownBlockType.taskList,
    ),
    _SlashCommandOption.text(
      label: 'Quote',
      keywords: 'quote 引用',
      icon: Icons.format_quote_rounded,
      type: MarkdownBlockType.quote,
    ),
    _SlashCommandOption.text(
      label: 'Divider',
      keywords: 'divider hr 分割线',
      icon: Icons.horizontal_rule_rounded,
      type: MarkdownBlockType.thematicBreak,
    ),
    _SlashCommandOption.text(
      label: 'Code',
      keywords: 'code block 代码块',
      icon: Icons.code_rounded,
      type: MarkdownBlockType.codeFence,
    ),
    _SlashCommandOption.text(
      label: 'Image',
      keywords: 'image 图片',
      icon: Icons.image_outlined,
      type: MarkdownBlockType.image,
    ),
    _SlashCommandOption.text(
      label: 'Table',
      keywords: 'table 表格',
      icon: Icons.table_chart_outlined,
      type: MarkdownBlockType.table,
    ),
  ];

  void _handleSlashCommand(_SlashCommandOption command) {
    if (command.level != null) {
      widget.controller.convertBlockToHeading(widget.block.id, command.level!);
      return;
    }
    widget.controller.convertBlock(widget.block.id, command.type);
  }

  void _handleBlockTrigger(_BlockTrigger trigger) {
    switch (trigger.type) {
      case _BlockTriggerType.heading1:
        widget.controller.convertBlockToHeading(widget.block.id, 1);
      case _BlockTriggerType.heading2:
        widget.controller.convertBlockToHeading(widget.block.id, 2);
      case _BlockTriggerType.heading3:
        widget.controller.convertBlockToHeading(widget.block.id, 3);
      case _BlockTriggerType.heading4:
        widget.controller.convertBlockToHeading(widget.block.id, 4);
      case _BlockTriggerType.heading5:
        widget.controller.convertBlockToHeading(widget.block.id, 5);
      case _BlockTriggerType.heading6:
        widget.controller.convertBlockToHeading(widget.block.id, 6);
      case _BlockTriggerType.quote:
        widget.controller.convertBlock(
          widget.block.id,
          MarkdownBlockType.quote,
        );
      case _BlockTriggerType.bulletList:
        widget.controller.convertBlock(
          widget.block.id,
          MarkdownBlockType.bulletList,
        );
      case _BlockTriggerType.orderedList:
        widget.controller.convertBlock(
          widget.block.id,
          MarkdownBlockType.orderedList,
        );
      case _BlockTriggerType.taskList:
        widget.controller.convertBlock(
          widget.block.id,
          MarkdownBlockType.taskList,
        );
      case _BlockTriggerType.thematicBreak:
        widget.controller.convertBlock(
          widget.block.id,
          MarkdownBlockType.thematicBreak,
        );
    }
  }

  void _focusPreviousBlock() {
    final blocks = widget.controller.blocks;
    if (widget.index <= 0) return;
    final prevId = blocks[widget.index - 1].id;
    widget.onRequestFocus(prevId, cursorOffset: null);
  }

  void _focusNextBlock() {
    final blocks = widget.controller.blocks;
    if (widget.index >= blocks.length - 1) return;
    final nextId = blocks[widget.index + 1].id;
    widget.onRequestFocus(nextId, cursorOffset: 0);
  }

  void _mergeWithPreviousBlock() {
    if (widget.index <= 0) {
      _deleteCurrentBlockIfPossible();
      return;
    }
    final result = widget.controller.mergeBlockWithPrevious(widget.block.id);
    if (result != null) {
      widget.onRequestFocus(result.blockId, cursorOffset: result.cursorOffset);
    }
  }

  void _deleteCurrentBlockIfPossible() {
    if (widget.controller.blocks.length <= 1) {
      widget.controller.convertBlock(
        widget.block.id,
        MarkdownBlockType.paragraph,
      );
      widget.controller.updateParagraphLikeBlock(
        widget.block.id,
        const StyledTextValue(text: ''),
        recordHistory: false,
      );
      return;
    }
    widget.controller.deleteBlock(widget.block.id);
  }

  void _handleEmptyListItemBackspace(int itemIndex) {
    if (widget.block.items.length > 1) {
      widget.controller.removeListItem(widget.block.id, itemIndex);
      return;
    }
    widget.controller.convertBlock(
      widget.block.id,
      MarkdownBlockType.paragraph,
    );
  }
}

class _AddBlockBar extends StatelessWidget {
  const _AddBlockBar({required this.onAdd});

  final ValueChanged<MarkdownBlockType> onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9CEBC)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final type in const [
            MarkdownBlockType.paragraph,
            MarkdownBlockType.heading,
            MarkdownBlockType.quote,
            MarkdownBlockType.orderedList,
            MarkdownBlockType.taskList,
            MarkdownBlockType.table,
            MarkdownBlockType.codeFence,
            MarkdownBlockType.footnote,
          ])
            ActionChip(
              label: Text(type.label),
              avatar: const Icon(Icons.add_rounded, size: 18),
              onPressed: () => onAdd(type),
            ),
        ],
      ),
    );
  }
}

class _SourcePane extends StatelessWidget {
  const _SourcePane({
    required this.controller,
    required this.focusNode,
    required this.onActivateEditor,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(TextEditingController, FocusNode) onActivateEditor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Markdown 源码',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '这里是纯 Markdown 编辑模式，右侧预览按 GFM 规则实时更新。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF68737D)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onTap: () => onActivateEditor(controller, focusNode),
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.55,
              ),
              decoration: const InputDecoration(
                labelText: 'GFM Markdown',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFFFFCF7),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview({required this.markdown, required this.onTapLink});

  final String markdown;
  final void Function(String text, String? href, String title) onTapLink;

  @override
  Widget build(BuildContext context) {
    final content = markdown.trim().isEmpty ? '_文档为空_' : markdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '实时预览',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '源码模式下的 GFM 渲染结果。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF68737D)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: MarkdownBody(
              data: content,
              selectable: true,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              styleSheet: _gfmStyleSheet(context),
              onTapLink: onTapLink,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.82),
        border: Border.all(color: const Color(0xFFE4D9C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

enum _BlockTriggerType {
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  quote,
  bulletList,
  orderedList,
  taskList,
  thematicBreak,
}

class _BlockTrigger {
  const _BlockTrigger(this.type, this.strippedText);

  final _BlockTriggerType type;
  final String strippedText;
}

_BlockTrigger? _detectBlockTrigger(String text) {
  if (text.contains('\n')) {
    return null;
  }

  final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(text);
  if (headingMatch != null) {
    final level = headingMatch.group(1)!.length;
    return _BlockTrigger(
      _BlockTriggerType.values[level - 1],
      headingMatch.group(2) ?? '',
    );
  }

  final quoteMatch = RegExp(r'^>\s?(.*)$').firstMatch(text);
  if (quoteMatch != null) {
    return _BlockTrigger(_BlockTriggerType.quote, quoteMatch.group(1) ?? '');
  }

  final taskMatch = RegExp(r'^[-*+]\s+\[[ xX]\]\s+(.*)$').firstMatch(text);
  if (taskMatch != null) {
    return _BlockTrigger(_BlockTriggerType.taskList, taskMatch.group(1) ?? '');
  }

  final orderedMatch = RegExp(r'^\d+\.\s+(.*)$').firstMatch(text);
  if (orderedMatch != null) {
    return _BlockTrigger(
      _BlockTriggerType.orderedList,
      orderedMatch.group(1) ?? '',
    );
  }

  final bulletMatch = RegExp(r'^[-*+]\s+(.*)$').firstMatch(text);
  if (bulletMatch != null) {
    return _BlockTrigger(
      _BlockTriggerType.bulletList,
      bulletMatch.group(1) ?? '',
    );
  }

  if (RegExp(r'^-{3,}\s*$').hasMatch(text)) {
    return const _BlockTrigger(_BlockTriggerType.thematicBreak, '');
  }

  return null;
}

class _SlashCommandOption {
  const _SlashCommandOption.text({
    required this.label,
    required this.keywords,
    required this.icon,
    this.type = MarkdownBlockType.paragraph,
  }) : level = null;

  const _SlashCommandOption.heading({
    required this.label,
    required this.keywords,
    required this.icon,
    required this.level,
  }) : type = MarkdownBlockType.heading;

  final String label;
  final String keywords;
  final IconData icon;
  final MarkdownBlockType type;
  final int? level;
}

class _SlashCommandMenu extends StatelessWidget {
  const _SlashCommandMenu({
    required this.commands,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SlashCommandOption> commands;
  final int selectedIndex;
  final ValueChanged<_SlashCommandOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4D9C8)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 8),
            color: Color(0x1417212B),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < commands.length; i++)
            Material(
              color: i == selectedIndex
                  ? const Color(0xFFEFF7F5)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(commands[i]),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(commands[i].icon, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          commands[i].label,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlainMultilineField extends StatefulWidget {
  const _PlainMultilineField({
    required this.text,
    required this.hintText,
    required this.style,
    required this.onActivateEditor,
    required this.onChanged,
    this.onEditingStarted,
    this.onEditingEnded,
    this.fillColor = const Color(0xFFFFFCF7),
    this.borderColor = const Color(0xFFE0D5C8),
    this.dense = false,
  });

  final String text;
  final String hintText;
  final TextStyle style;
  final void Function(TextEditingController, FocusNode) onActivateEditor;
  final ValueChanged<String> onChanged;
  final VoidCallback? onEditingStarted;
  final VoidCallback? onEditingEnded;
  final Color fillColor;
  final Color borderColor;
  final bool dense;

  @override
  State<_PlainMultilineField> createState() => _PlainMultilineFieldState();
}

class _PlainMultilineFieldState extends State<_PlainMultilineField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _syncing = false;
  String _lastObservedText = '';
  TextSelection? _lastObservedSelection;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text)
      ..addListener(_handleChanged);
    _rememberControllerSnapshot();
    _focusNode = FocusNode()
      ..addListener(() {
        if (_focusNode.hasFocus) {
          widget.onEditingStarted?.call();
          widget.onActivateEditor(_controller, _focusNode);
        } else {
          widget.onEditingEnded?.call();
        }
      });
  }

  @override
  void didUpdateWidget(covariant _PlainMultilineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _controller.text) {
      return;
    }
    _syncing = true;
    final selection = _controller.selection;
    final offset = selection.isValid
        ? selection.baseOffset.clamp(0, widget.text.length)
        : widget.text.length;
    _controller.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _syncing = false;
    _rememberControllerSnapshot();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (_syncing) {
      return;
    }
    final previousSelection = _lastObservedSelection;
    final textChanged = _controller.text != _lastObservedText;
    _rememberControllerSnapshot();
    if (!textChanged) {
      _maybeShowSelectionToolbar(previousSelection);
      return;
    }
    widget.onChanged(_controller.text);
  }

  void _rememberControllerSnapshot() {
    _lastObservedText = _controller.text;
    _lastObservedSelection = _controller.selection;
  }

  void _maybeShowSelectionToolbar(TextSelection? previousSelection) {
    final selection = _controller.selection;
    if (!_focusNode.hasFocus ||
        !selection.isValid ||
        selection.isCollapsed) {
      return;
    }
    // 当有选中文本时显示工具栏（双击或拖动选中）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) {
        return;
      }
      _findEditableTextState()?.showToolbar();
    });
  }

  EditableTextState? _findEditableTextState() {
    EditableTextState? result;

    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return result;
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return AdaptiveTextSelectionToolbar.editableText(
      editableTextState: editableTextState,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      contextMenuBuilder: _buildContextMenu,
      onTap: () => widget.onActivateEditor(_controller, _focusNode),
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: widget.style,
      decoration: InputDecoration(
        hintText: widget.hintText,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: widget.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: widget.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        filled: true,
        fillColor: widget.fillColor,
        isDense: widget.dense,
      ),
    );
  }
}

class _RichMarkdownField extends StatefulWidget {
  const _RichMarkdownField({
    super.key,
    required this.value,
    required this.style,
    required this.hintText,
    required this.onActivateEditor,
    required this.onChanged,
    this.onEditingStarted,
    this.onEditingEnded,
    this.onEnterPressed,
    this.onBackspaceOnEmpty,
    this.onSlashCommandSelected,
    this.onBlockTriggerDetected,
    this.onFocusNextBlock,
    this.onFocusPreviousBlock,
    this.onSplitBlock,
    this.onMergeWithPrevious,
    this.slashCommands = const <_SlashCommandOption>[],
  });

  final StyledTextValue value;
  final TextStyle style;
  final String hintText;
  final void Function(TextEditingController, FocusNode) onActivateEditor;
  final ValueChanged<StyledTextValue> onChanged;
  final VoidCallback? onEditingStarted;
  final VoidCallback? onEditingEnded;
  final VoidCallback? onEnterPressed;
  final VoidCallback? onBackspaceOnEmpty;
  final ValueChanged<_SlashCommandOption>? onSlashCommandSelected;
  final ValueChanged<_BlockTrigger>? onBlockTriggerDetected;

  /// Called with cursor offset when Enter is pressed to split the block.
  final void Function(int cursorOffset)? onSplitBlock;

  /// Called when Backspace is at start — requests focus on previous block at end.
  final VoidCallback? onMergeWithPrevious;

  /// Called when Up arrow is at the start — requests focus on previous block.
  final VoidCallback? onFocusPreviousBlock;

  /// Called when Down arrow is at the end — requests focus on next block.
  final VoidCallback? onFocusNextBlock;
  final List<_SlashCommandOption> slashCommands;

  @override
  State<_RichMarkdownField> createState() => _RichMarkdownFieldState();
}

class _RichMarkdownFieldState extends State<_RichMarkdownField> {
  late final _RichMarkdownController _controller;
  late final FocusNode _focusNode;
  late final LayerLink _layerLink;
  bool _syncing = false;
  int _slashSelectionIndex = 0;
  OverlayEntry? _slashOverlay;
  String _lastObservedText = '';
  TextSelection? _lastObservedSelection;

  @override
  void initState() {
    super.initState();
    _controller = _RichMarkdownController(
      richValue: widget.value,
      baseStyle: widget.style,
    )..addListener(_handleTextChanged);
    _rememberControllerSnapshot();
    _layerLink = LayerLink();
    _focusNode = FocusNode()
      ..addListener(() {
        if (_focusNode.hasFocus) {
          widget.onEditingStarted?.call();
          widget.onActivateEditor(_controller, _focusNode);
        } else {
          widget.onEditingEnded?.call();
          _dismissSlashOverlay();
        }
      });
  }

  @override
  void didUpdateWidget(covariant _RichMarkdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.baseStyle = widget.style;
    if (_sameStyledValue(widget.value, _controller.richValue)) {
      return;
    }
    _syncing = true;
    _controller.syncValue(widget.value);
    _syncing = false;
    _rememberControllerSnapshot();
  }

  @override
  void dispose() {
    _dismissSlashOverlay();
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissSlashOverlay() {
    _slashOverlay?.remove();
    _slashOverlay = null;
  }

  void _showSlashOverlay(List<_SlashCommandOption> options) {
    _dismissSlashOverlay();
    _slashOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 360,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 4),
          child: _SlashCommandMenu(
            commands: options,
            selectedIndex: _slashSelectionIndex.clamp(0, options.length - 1),
            onSelected: _applySlashCommand,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_slashOverlay!);
  }

  void _handleTextChanged() {
    if (_syncing) {
      return;
    }

    final previousSelection = _lastObservedSelection;
    final text = _controller.text;
    final textChanged = text != _lastObservedText;
    _rememberControllerSnapshot();

    if (!textChanged) {
      _updateSlashOverlay();
      _maybeShowSelectionToolbar(previousSelection);
      return;
    }

    // 中文输入法合成期间跳过处理，避免打断输入
    if (_controller.value.composing.isValid) {
      return;
    }

    // Intercept block-level trigger syntax before inline transformation.
    final trigger = _detectBlockTrigger(text);
    if (trigger != null && widget.onBlockTriggerDetected != null) {
      _syncing = true;
      _controller.syncValue(
        StyledTextValue(text: trigger.strippedText),
        selection: TextSelection.collapsed(offset: trigger.strippedText.length),
      );
      _syncing = false;
      _rememberControllerSnapshot();
      widget.onBlockTriggerDetected!(trigger);
      return;
    }

    final result = _transformInlineInput(
      oldValue: _controller.richValue,
      newText: text,
      selection: _controller.selection,
    );
    _syncing = true;
    _controller.syncValue(result.value, selection: result.selection);
    _syncing = false;
    _rememberControllerSnapshot();
    widget.onChanged(result.value);
    _updateSlashOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          contextMenuBuilder: _buildContextMenu,
          onTap: () => widget.onActivateEditor(_controller, _focusNode),
          minLines: 1,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: widget.style,
          decoration: InputDecoration.collapsed(hintText: widget.hintText),
        ),
      ),
    );
  }

  void _rememberControllerSnapshot() {
    _lastObservedText = _controller.text;
    _lastObservedSelection = _controller.selection;
  }

  void _updateSlashOverlay() {
    if (!mounted) {
      return;
    }
    setState(() {
      final options = _filteredSlashCommands;
      if (options.isEmpty) {
        _slashSelectionIndex = 0;
        _dismissSlashOverlay();
      } else {
        if (_slashSelectionIndex >= options.length) {
          _slashSelectionIndex = options.length - 1;
        }
        _showSlashOverlay(options);
      }
    });
  }

  void _maybeShowSelectionToolbar(TextSelection? previousSelection) {
    final selection = _controller.selection;
    if (!_focusNode.hasFocus ||
        !selection.isValid ||
        selection.isCollapsed ||
        (previousSelection?.isCollapsed == false)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) {
        return;
      }
      _findEditableTextState()?.showToolbar();
    });
  }

  EditableTextState? _findEditableTextState() {
    EditableTextState? result;

    void visit(Element element) {
      if (result != null) {
        return;
      }
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return result;
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    final buttonItems = <ContextMenuButtonItem>[
      if (!selection.isCollapsed)
        ContextMenuButtonItem(
          label: '加粗',
          onPressed: () {
            editableTextState.hideToolbar();
            _toggleMark(InlineMarkType.bold);
          },
        ),
      if (!selection.isCollapsed)
        ContextMenuButtonItem(
          label: '斜体',
          onPressed: () {
            editableTextState.hideToolbar();
            _toggleMark(InlineMarkType.italic);
          },
        ),
      if (!selection.isCollapsed)
        ContextMenuButtonItem(
          label: '链接',
          onPressed: () {
            editableTextState.hideToolbar();
            _insertOrUpdateLink();
          },
        ),
      ...editableTextState.contextMenuButtonItems,
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_hasModifierShortcut(event, LogicalKeyboardKey.keyB)) {
      _toggleMark(InlineMarkType.bold);
      return KeyEventResult.handled;
    }
    if (_hasModifierShortcut(event, LogicalKeyboardKey.keyI)) {
      _toggleMark(InlineMarkType.italic);
      return KeyEventResult.handled;
    }
    if (_hasModifierShortcut(event, LogicalKeyboardKey.keyK)) {
      _insertOrUpdateLink();
      return KeyEventResult.handled;
    }

    if (_filteredSlashCommands.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissSlashOverlay();
        setState(() => _slashSelectionIndex = 0);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _slashSelectionIndex =
              (_slashSelectionIndex + 1) % _filteredSlashCommands.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _slashSelectionIndex =
              (_slashSelectionIndex - 1 + _filteredSlashCommands.length) %
              _filteredSlashCommands.length;
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _applySlashCommand(_filteredSlashCommands[_slashSelectionIndex]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (widget.onSplitBlock != null) {
        widget.onSplitBlock!(_controller.selection.baseOffset);
        return KeyEventResult.handled;
      }
      if (widget.onEnterPressed != null) {
        widget.onEnterPressed!.call();
        return KeyEventResult.handled;
      }
    }

    // Arrow Up at start → focus previous block.
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _controller.selection.baseOffset == 0 &&
        widget.onFocusPreviousBlock != null) {
      widget.onFocusPreviousBlock!.call();
      return KeyEventResult.handled;
    }

    // Arrow Down at end → focus next block.
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _controller.selection.baseOffset >= _controller.text.length &&
        widget.onFocusNextBlock != null) {
      widget.onFocusNextBlock!.call();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controller.text.isEmpty && widget.onBackspaceOnEmpty != null) {
        widget.onBackspaceOnEmpty!.call();
        return KeyEventResult.handled;
      }
      // Backspace at start of field → merge with previous block.
      if (_controller.selection.baseOffset == 0 &&
          _controller.selection.extentOffset == 0 &&
          widget.onMergeWithPrevious != null) {
        widget.onMergeWithPrevious!.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void requestFocus({int? cursorOffset}) {
    _focusNode.requestFocus();
    if (cursorOffset != null) {
      // 延迟到下一帧，确保 didUpdateWidget 已经完成且焦点已获取
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 确保焦点在下一帧时设置
        _focusNode.requestFocus();
        if (_focusNode.hasFocus) {
          _controller.selection = TextSelection.collapsed(
            offset: cursorOffset.clamp(0, _controller.text.length),
          );
        }
      });
    }
  }

  bool _hasModifierShortcut(KeyEvent event, LogicalKeyboardKey key) {
    return event.logicalKey == key &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
  }

  String? get _slashQuery {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final offset = selection.baseOffset;
    final searchEnd = offset - 1;
    final lineStart = searchEnd < 0
        ? 0
        : _controller.text.lastIndexOf('\n', searchEnd) + 1;
    final prefix = _controller.text.substring(lineStart, offset);
    final trimmed = prefix.trimLeft();
    if (!trimmed.startsWith('/')) {
      return null;
    }
    return trimmed.substring(1);
  }

  List<_SlashCommandOption> get _filteredSlashCommands {
    final query = _slashQuery;
    if (query == null) {
      return const <_SlashCommandOption>[];
    }
    if (widget.slashCommands.isEmpty) {
      return const <_SlashCommandOption>[];
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return widget.slashCommands;
    }
    return widget.slashCommands
        .where((command) {
          return command.label.toLowerCase().contains(normalized) ||
              command.keywords.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  void _applySlashCommand(_SlashCommandOption command) {
    _dismissSlashOverlay();
    widget.onSlashCommandSelected?.call(command);
    if (mounted) {
      setState(() => _slashSelectionIndex = 0);
    }
  }

  void _toggleMark(InlineMarkType type) {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final current = _controller.richValue;
    final hasCoveringMark = current.marks.any(
      (mark) => mark.type == type && mark.start <= start && mark.end >= end,
    );
    final nextMarks = <InlineMark>[];
    for (final mark in current.marks) {
      if (mark.type != type || mark.end <= start || mark.start >= end) {
        nextMarks.add(mark.copyWith());
        continue;
      }
      if (mark.start < start) {
        nextMarks.add(mark.copyWith(end: start));
      }
      if (mark.end > end) {
        nextMarks.add(mark.copyWith(start: end));
      }
    }
    if (!hasCoveringMark) {
      nextMarks.add(InlineMark(start: start, end: end, type: type));
    }

    _applyValue(
      current.copyWith(
        marks: nextMarks
          ..sort((left, right) => left.start.compareTo(right.start)),
      ),
      selection,
    );
  }

  Future<void> _insertOrUpdateLink() async {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed || !mounted) {
      return;
    }
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('插入链接'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'https://example.com'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) {
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final current = _controller.richValue;
    final nextMarks = <InlineMark>[];
    for (final mark in current.marks) {
      if (mark.type != InlineMarkType.link ||
          mark.end <= start ||
          mark.start >= end) {
        nextMarks.add(mark.copyWith());
        continue;
      }
      if (mark.start < start) {
        nextMarks.add(mark.copyWith(end: start));
      }
      if (mark.end > end) {
        nextMarks.add(mark.copyWith(start: end));
      }
    }
    nextMarks.add(
      InlineMark(start: start, end: end, type: InlineMarkType.link, data: url),
    );
    _applyValue(
      current.copyWith(
        marks: nextMarks
          ..sort((left, right) => left.start.compareTo(right.start)),
      ),
      selection,
    );
  }

  void _applyValue(StyledTextValue value, TextSelection selection) {
    _syncing = true;
    _controller.syncValue(value, selection: selection);
    _syncing = false;
    widget.onChanged(value);
    if (mounted) {
      setState(() {});
    }
  }
}

class _RichMarkdownController extends TextEditingController {
  _RichMarkdownController({
    required StyledTextValue richValue,
    required this.baseStyle,
  }) : richValue = richValue.clone(),
       super(text: richValue.text);

  StyledTextValue richValue;
  TextStyle baseStyle;

  void syncValue(StyledTextValue next, {TextSelection? selection}) {
    richValue = next.clone();
    if (text != next.text) {
      // 保留 composing 范围以支持中文输入法
      value = TextEditingValue(
        text: next.text,
        selection:
            selection ?? TextSelection.collapsed(offset: next.text.length),
        composing: value.composing,
      );
      return;
    }
    if (selection != null) {
      value = value.copyWith(selection: selection);
    } else {
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final textLength = richValue.text.length;
    final boundaries = <int>{0, textLength};
    
    for (final mark in richValue.marks) {
      boundaries
        ..add(mark.start.clamp(0, textLength))
        ..add(mark.end.clamp(0, textLength));
    }
    
    // 添加输入法合成范围的边界（限制在文本长度内）
    if (withComposing && value.composing.isValid) {
      boundaries
        ..add(value.composing.start.clamp(0, textLength))
        ..add(value.composing.end.clamp(0, textLength));
    }
    
    final sorted = boundaries.toList()..sort();

    for (var i = 0; i < sorted.length - 1; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (end <= start || start >= textLength) {
        continue;
      }

      final segment = richValue.text.substring(start, end.clamp(start, textLength));
      final activeMarks = richValue.marks
          .where((mark) => mark.start <= start && mark.end >= end)
          .toList(growable: false);
      var segmentStyle = baseStyle;
      
      // 应用 marks 样式
      for (final mark in activeMarks) {
        switch (mark.type) {
          case InlineMarkType.bold:
            segmentStyle = segmentStyle.copyWith(fontWeight: FontWeight.w800);
          case InlineMarkType.italic:
            segmentStyle = segmentStyle.copyWith(fontStyle: FontStyle.italic);
          case InlineMarkType.strike:
            segmentStyle = segmentStyle.copyWith(
              decoration: TextDecoration.lineThrough,
            );
          case InlineMarkType.code:
            segmentStyle = segmentStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0xFFEFE8DA),
            );
          case InlineMarkType.link:
            segmentStyle = segmentStyle.copyWith(
              color: const Color(0xFF0F766E),
              decoration: TextDecoration.underline,
            );
          case InlineMarkType.footnoteRef:
            segmentStyle = segmentStyle.copyWith(
              color: const Color(0xFF0F766E),
              fontSize: (segmentStyle.fontSize ?? 16) * 0.78,
              fontWeight: FontWeight.w800,
            );
        }
      }
      
      // 应用输入法合成范围的下划线样式
      if (withComposing &&
          value.composing.isValid &&
          start >= value.composing.start &&
          end <= value.composing.end) {
        segmentStyle = segmentStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFF0F766E),
        );
      }
      
      spans.add(TextSpan(text: segment, style: segmentStyle));
    }

    return TextSpan(style: style ?? baseStyle, children: spans);
  }
}

class _InlineEditResult {
  const _InlineEditResult({required this.value, required this.selection});

  final StyledTextValue value;
  final TextSelection selection;
}

_InlineEditResult _transformInlineInput({
  required StyledTextValue oldValue,
  required String newText,
  required TextSelection selection,
}) {
  final preservedMarks = _preserveMarksAfterEdit(oldValue, newText);
  var working = StyledTextValue(text: newText, marks: preservedMarks);
  var offset = selection.isValid ? selection.baseOffset : newText.length;

  final syntaxRules = <_InlineSyntaxRule>[
    _InlineSyntaxRule(
      expression: RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      apply: (value, match) {
        final label = match.group(1) ?? '';
        final url = match.group(2) ?? '';
        return _replaceRange(value, match.start, match.end, label, <InlineMark>[
          InlineMark(
            start: 0,
            end: label.length,
            type: InlineMarkType.link,
            data: url,
          ),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'`([^`]+)`'),
      apply: (value, match) {
        final text = match.group(1) ?? '';
        return _replaceRange(value, match.start, match.end, text, <InlineMark>[
          InlineMark(start: 0, end: text.length, type: InlineMarkType.code),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'(?<!\*)\*\*([^*\n]+)\*\*(?!\*)'),
      apply: (value, match) {
        final text = match.group(1) ?? '';
        return _replaceRange(value, match.start, match.end, text, <InlineMark>[
          InlineMark(start: 0, end: text.length, type: InlineMarkType.bold),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'~~([^~]+)~~'),
      apply: (value, match) {
        final text = match.group(1) ?? '';
        return _replaceRange(value, match.start, match.end, text, <InlineMark>[
          InlineMark(start: 0, end: text.length, type: InlineMarkType.strike),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'),
      apply: (value, match) {
        final text = match.group(1) ?? '';
        return _replaceRange(value, match.start, match.end, text, <InlineMark>[
          InlineMark(start: 0, end: text.length, type: InlineMarkType.italic),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'(?<!_)_([^_\n]+)_(?!_)'),
      apply: (value, match) {
        final text = match.group(1) ?? '';
        return _replaceRange(value, match.start, match.end, text, <InlineMark>[
          InlineMark(start: 0, end: text.length, type: InlineMarkType.italic),
        ]);
      },
    ),
    _InlineSyntaxRule(
      expression: RegExp(r'\[\^([^\]]+)\]'),
      apply: (value, match) {
        final id = match.group(1) ?? '';
        final visible = '[$id]';
        return _replaceRange(
          value,
          match.start,
          match.end,
          visible,
          <InlineMark>[
            InlineMark(
              start: 0,
              end: visible.length,
              type: InlineMarkType.footnoteRef,
              data: id,
            ),
          ],
        );
      },
    ),
  ];

  for (final rule in syntaxRules) {
    final matches = rule.expression
        .allMatches(working.text)
        .toList(growable: false);
    for (final match in matches.reversed) {
      if (_overlapsExistingMark(working.marks, match.start, match.end)) {
        continue;
      }
      final replacementLength = rule.visibleLength(match);
      offset = _adjustOffsetAfterReplacement(
        offset: offset,
        start: match.start,
        end: match.end,
        replacementLength: replacementLength,
      );
      working = rule.apply(working, match);
    }
  }

  return _InlineEditResult(
    value: working,
    selection: TextSelection.collapsed(
      offset: offset.clamp(0, working.text.length),
    ),
  );
}

List<InlineMark> _preserveMarksAfterEdit(
  StyledTextValue oldValue,
  String newText,
) {
  if (oldValue.text == newText) {
    return oldValue.marks
        .map((mark) => mark.copyWith())
        .toList(growable: false);
  }

  final oldText = oldValue.text;
  var prefix = 0;
  while (prefix < oldText.length &&
      prefix < newText.length &&
      oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }

  var suffix = 0;
  while (suffix < oldText.length - prefix &&
      suffix < newText.length - prefix &&
      oldText.codeUnitAt(oldText.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }

  final oldChangedEnd = oldText.length - suffix;
  final newChangedEnd = newText.length - suffix;
  final oldChangedLength = oldChangedEnd - prefix;
  final newChangedLength = newChangedEnd - prefix;
  final delta = newChangedLength - oldChangedLength;

  final marks = <InlineMark>[];
  for (final mark in oldValue.marks) {
    if (oldChangedLength == 0) {
      final insertAt = prefix;
      if (mark.end <= insertAt) {
        marks.add(mark.copyWith());
      } else if (mark.start >= insertAt) {
        marks.add(
          mark.copyWith(start: mark.start + delta, end: mark.end + delta),
        );
      } else if (mark.start < insertAt && mark.end >= insertAt) {
        marks.add(mark.copyWith(end: mark.end + delta));
      }
      continue;
    }

    if (mark.end <= prefix) {
      marks.add(mark.copyWith());
      continue;
    }
    if (mark.start >= oldChangedEnd) {
      marks.add(
        mark.copyWith(start: mark.start + delta, end: mark.end + delta),
      );
      continue;
    }
    if (mark.start <= prefix && mark.end >= oldChangedEnd) {
      marks.add(mark.copyWith(end: mark.end + delta));
    }
  }

  return marks.where((mark) => mark.end > mark.start).toList(growable: false);
}

bool _overlapsExistingMark(List<InlineMark> marks, int start, int end) {
  for (final mark in marks) {
    if (mark.end > start && mark.start < end) {
      return true;
    }
  }
  return false;
}

int _adjustOffsetAfterReplacement({
  required int offset,
  required int start,
  required int end,
  required int replacementLength,
}) {
  if (offset <= start) {
    return offset;
  }
  if (offset >= end) {
    return offset + replacementLength - (end - start);
  }
  return start + replacementLength;
}

StyledTextValue _replaceRange(
  StyledTextValue value,
  int start,
  int end,
  String replacement,
  List<InlineMark> addedMarks,
) {
  final before = value.slice(0, start);
  final after = value.slice(end, value.text.length);
  final shiftedAdded = addedMarks
      .map(
        (mark) => mark.copyWith(
          start: mark.start + before.text.length,
          end: mark.end + before.text.length,
        ),
      )
      .toList(growable: false);
  final shiftedAfter = after.marks
      .map(
        (mark) => mark.copyWith(
          start: mark.start + before.text.length + replacement.length,
          end: mark.end + before.text.length + replacement.length,
        ),
      )
      .toList(growable: false);
  return StyledTextValue(
    text: before.text + replacement + after.text,
    marks: <InlineMark>[...before.marks, ...shiftedAdded, ...shiftedAfter],
  );
}

bool _sameStyledValue(StyledTextValue a, StyledTextValue b) {
  if (a.text != b.text || a.marks.length != b.marks.length) {
    return false;
  }
  for (var i = 0; i < a.marks.length; i++) {
    final left = a.marks[i];
    final right = b.marks[i];
    if (left.start != right.start ||
        left.end != right.end ||
        left.type != right.type ||
        left.data != right.data) {
      return false;
    }
  }
  return true;
}

class _InlineSyntaxRule {
  const _InlineSyntaxRule({required this.expression, required this.apply});

  final RegExp expression;
  final StyledTextValue Function(StyledTextValue value, Match match) apply;

  int visibleLength(Match match) {
    if (match.groupCount >= 1 && expression.pattern.contains(r'\[\^')) {
      return (match.group(1) ?? '').length + 2;
    }
    return (match.group(1) ?? '').length;
  }
}

TextStyle _blockStyle(BuildContext context, MarkdownBlock block) {
  final theme = Theme.of(context).textTheme;
  return switch (block.type) {
    MarkdownBlockType.heading => switch (block.level) {
      1 =>
        theme.headlineMedium?.copyWith(fontWeight: FontWeight.w800) ??
            const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
      2 =>
        theme.headlineSmall?.copyWith(fontWeight: FontWeight.w800) ??
            const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      3 =>
        theme.titleLarge?.copyWith(fontWeight: FontWeight.w800) ??
            const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      _ =>
        theme.titleMedium?.copyWith(fontWeight: FontWeight.w800) ??
            const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    }.copyWith(height: 1.35),
    MarkdownBlockType.quote =>
      theme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
            height: 1.7,
            color: const Color(0xFF3F4852),
          ) ??
          const TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: 16,
            height: 1.7,
          ),
    _ =>
      theme.bodyLarge?.copyWith(height: 1.7) ??
          const TextStyle(fontSize: 16, height: 1.7),
  };
}

MarkdownStyleSheet _gfmStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final base = MarkdownStyleSheet.fromTheme(theme);
  return base.copyWith(
    p: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
    h1: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
    h2: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    h3: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    blockquote: theme.textTheme.bodyLarge?.copyWith(
      fontStyle: FontStyle.italic,
      color: const Color(0xFF40505E),
      height: 1.7,
    ),
    blockquoteDecoration: BoxDecoration(
      color: const Color(0xFFF7F4ED),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: Color(0xFF0F766E), width: 4),
      ),
    ),
    code: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      backgroundColor: Color(0xFFEFE8DA),
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(14),
    ),
    tableHead: const TextStyle(fontWeight: FontWeight.w800),
    tableBody: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
    tableBorder: TableBorder.all(color: const Color(0xFFDCCFBF)),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    a: const TextStyle(
      color: Color(0xFF0F766E),
      decoration: TextDecoration.underline,
    ),
  );
}
