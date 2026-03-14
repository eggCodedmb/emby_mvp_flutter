import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeStore extends ChangeNotifier {
  bool _isDark = true;
  bool _ready = false;

  bool get isDark => _isDark;
  bool get isReady => _ready;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _isDark = sp.getBool('isDarkMode') ?? true;
    _ready = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDark = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('isDarkMode', value);
    notifyListeners();
  }
}
