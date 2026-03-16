import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/auth_store.dart';
import 'core/theme_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthStore()..init()),
        ChangeNotifierProvider(create: (_) => ThemeStore()..init()),
      ],
      child: const EmbyMvpApp(),
    ),
  );
}
