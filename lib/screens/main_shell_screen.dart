import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShellScreen extends StatelessWidget {
  const MainShellScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = location.startsWith('/me') ? 1 : 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
            ),
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      label: '首页',
                      selected: currentIndex == 0,
                      normalAsset: 'assets/NavigationBar/nav_home.png',
                      activeAsset: 'assets/NavigationBar/nav_home_active.png',
                      onTap: () => context.go('/library'),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      label: '我的',
                      selected: currentIndex == 1,
                      normalAsset: 'assets/NavigationBar/nav_profile.png',
                      activeAsset: 'assets/NavigationBar/nav_profile_active.png',
                      onTap: () => context.go('/me'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.normalAsset,
    required this.activeAsset,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final String normalAsset;
  final String activeAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Image.asset(selected ? activeAsset : normalAsset),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? const Color(0xFF60A5FA) : Colors.white70,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
