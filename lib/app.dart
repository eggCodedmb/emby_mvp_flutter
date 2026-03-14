import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/media_detail_screen.dart';
import 'screens/media_list_screen.dart';
import 'screens/player_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/profile_screen.dart';

class EmbyMvpApp extends StatelessWidget {
  const EmbyMvpApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();

    final router = GoRouter(
      initialLocation: '/media',
      redirect: (context, state) {
        if (!auth.isReady) return null;
        final loggingIn = state.matchedLocation == '/login';
        if (!auth.isLoggedIn && !loggingIn) return '/login';
        if (auth.isLoggedIn && loggingIn) return '/media';
        return null;
      },
      refreshListenable: auth,
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, state) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShellScreen(child: child),
          routes: [
            GoRoute(
              path: '/media',
              builder: (_, state) => const MediaListScreen(),
            ),
            GoRoute(
              path: '/me',
              builder: (_, state) => const ProfileScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/media/:id',
          builder: (_, state) {
            final id = int.parse(state.pathParameters['id']!);
            return MediaDetailScreen(mediaId: id);
          },
        ),
        GoRoute(
          path: '/player/:id',
          builder: (_, state) {
            final id = int.parse(state.pathParameters['id']!);
            final title = state.uri.queryParameters['title'] ?? '播放器';
            return PlayerScreen(mediaId: id, title: title);
          },
        ),
        GoRoute(
          path: '/me/favorites',
          builder: (_, state) => const PlaceholderScreen(title: '我的收藏'),
        ),
        GoRoute(
          path: '/me/history',
          builder: (_, state) => const PlaceholderScreen(title: '历史记录'),
        ),
        GoRoute(
          path: '/me/settings',
          builder: (_, state) => const PlaceholderScreen(title: '设置'),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Emby MVP Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerConfig: router,
    );
  }
}
