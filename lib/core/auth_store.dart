import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

class AuthStore extends ChangeNotifier {
  bool _isReady = false;
  String? _token;

  bool get isReady => _isReady;
  bool get isLoggedIn => _token?.isNotEmpty == true;
  String? get token => _token;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
    await AuthService.syncToken(_token);
    _isReady = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final token = await AuthService.login(username: username, password: password);
    _token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    await AuthService.syncToken(null);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    notifyListeners();
  }
}
