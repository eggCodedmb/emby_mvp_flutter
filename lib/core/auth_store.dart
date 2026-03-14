import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

class AuthStore extends ChangeNotifier {
  bool _isReady = false;
  String? _token;
  String? _username;

  bool get isReady => _isReady;
  bool get isLoggedIn => _token?.isNotEmpty == true;
  String? get token => _token;
  String? get username => _username;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
    _username = sp.getString('username');
    await AuthService.syncToken(_token);
    _isReady = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final token = await AuthService.login(username: username, password: password);
    _token = token;
    _username = username;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await sp.setString('username', username);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    await AuthService.syncToken(null);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await sp.remove('username');
    notifyListeners();
  }
}
