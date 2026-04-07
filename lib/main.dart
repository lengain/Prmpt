import 'package:flutter/material.dart';
import 'package:ume/ume.dart';

import 'src/editor/editor_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PluginManager.instance
    ..register(WidgetInfoInspector())
    ..register(WidgetDetailInspector())
    ..register(ColorSucker())
    ..register(AlignRuler())
    ..register(ColorPicker())
    ..register(TouchIndicator());
  runApp(const UMEWidget(enable: true, child: PrmptApp()));
}
