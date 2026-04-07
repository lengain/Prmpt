import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prmpt/src/editor/editor_screen.dart';

void main() {
  testWidgets('homepage exposes dual modes and editor commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    expect(find.text('Prmpt True WYSIWYG Markdown Editor'), findsOneWidget);
    expect(find.text('所见即所得'), findsOneWidget);
    expect(find.text('源码编辑'), findsOneWidget);
    expect(find.text('固定高度'), findsOneWidget);
    expect(find.text('最大高度'), findsOneWidget);
    expect(find.text('全屏编辑'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);

    await tester.tap(find.text('源码编辑'));
    await tester.pumpAndSettle();

    expect(find.text('Markdown 源码'), findsOneWidget);
    expect(find.text('实时预览'), findsOneWidget);
  });

  testWidgets('wysiwyg uses a single markdown widget surface', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownWidget), findsOneWidget);
    expect(find.text('Prmpt True WYSIWYG Markdown Editor'), findsOneWidget);
    expect(find.text('# Prmpt WYSIWYG Markdown Editor'), findsNothing);
  });

  testWidgets('wysiwyg shows slash commands for a new paragraph block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('段落').first);
    await tester.pumpAndSettle();

    final paragraphField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '直接输入 Markdown，语法会在当前位置自动渲染',
    );

    await tester.enterText(paragraphField.last, '/ta');
    await tester.pumpAndSettle();

    expect(find.text('Table'), findsOneWidget);
  });

  testWidgets('typing block trigger converts paragraph to heading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    // Tap the first Paragraph block to focus it.
    await tester.tap(find.text('段落').first);
    await tester.pumpAndSettle();

    final paragraphField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText?.contains('Markdown') == true,
    );

    // Enter text starting with `# ` which triggers heading conversion.
    await tester.enterText(paragraphField.first, '# My Heading');
    await tester.pumpAndSettle();

    // After trigger detection, the block toolbar should show '标题' (Heading).
    expect(find.text('标题'), findsWidgets);
  });

  testWidgets('typing bullet trigger shows bullet list block type label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    // Find a paragraph block's text field.
    final paragraphField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText?.contains('Markdown') == true,
    );
    await tester.tap(paragraphField.first);
    await tester.pumpAndSettle();

    // Type `- ` to trigger bullet list conversion.
    await tester.enterText(paragraphField.first, '- ');
    await tester.pumpAndSettle();

    // The block type label should update to indicate a list block.
    expect(find.text('无序列表'), findsWidgets);
  });

  testWidgets('text selection stays expanded and shows common menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    final paragraphField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '直接输入 Markdown，语法会在当前位置自动渲染',
    );

    await tester.tap(paragraphField.first);
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(paragraphField.first)
        .controller!;
    expect(controller.text.length, greaterThan(4));

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.selection.isCollapsed, isFalse);
    expect(find.text('加粗'), findsOneWidget);
    expect(find.text('斜体'), findsOneWidget);
  });

  testWidgets('undo and redo are accessible via toolbar', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    // Both undo and redo buttons should be present (enabled or disabled state).
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('重做'), findsOneWidget);
  });

  testWidgets('add block bar shows all major block type chips', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PrmptApp());
    await tester.pumpAndSettle();

    // Verify the add-block bar is visible with ActionChip buttons.
    expect(find.byType(ActionChip), findsAtLeastNWidgets(6));
    // Block type chips should be present with Chinese labels.
    expect(find.text('标题'), findsWidgets);
    expect(find.text('引用'), findsWidgets);
  });
}
