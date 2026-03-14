import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/auth_store.dart';
import 'core/theme_store.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/media_detail_screen.dart';
import 'screens/media_list_screen.dart';
import 'screens/player_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';

class EmbyMvpApp extends StatelessWidget {
  const EmbyMvpApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      colorSchemeSeed: Colors.blue,
      useMaterial3: true,
      brightness: brightness,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: base.colorScheme.onSurface,
      displayColor: base.colorScheme.onSurface,
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: brightness == Brightness.dark ? const Color(0xFF0B1220) : const Color(0xFFF7F9FC),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final themeStore = context.watch<ThemeStore>();

    final router = GoRouter(
      initialLocation: '/library',
      redirect: (context, state) {
        if (!auth.isReady) return null;
        final loggingIn = state.matchedLocation == '/login';
        if (!auth.isLoggedIn && !loggingIn) return '/login';
        if (auth.isLoggedIn && loggingIn) return '/library';

        // 兼容旧路由
        if (auth.isLoggedIn && state.matchedLocation == '/media') {
          return '/library';
        }

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
              path: '/library',
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
          builder: (_, state) => const SettingsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Emby MVP Flutter',
      debugShowCheckedModeBanner: false,
      themeMode: themeStore.themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final clampedScale = media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
        return MediaQuery(
          data: media.copyWith(
            textScaler: clampedScale,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}
