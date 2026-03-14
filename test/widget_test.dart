import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:emby_mvp_flutter/app.dart';
import 'package:emby_mvp_flutter/core/auth_store.dart';

void main() {
  testWidgets('app renders', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthStore(),
        child: const EmbyMvpApp(),
      ),
    );

    expect(find.text('登录'), findsOneWidget);
  });
}
