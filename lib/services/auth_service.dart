import '../core/api_client.dart';

class AuthService {
  static Future<String> login({required String username, required String password}) async {
    final data = await apiClient.post('/api/auth/login', body: {
      'username': username,
      'password': password,
    }) as Map<String, dynamic>;

    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('登录成功但未返回 token');
    }
    await syncToken(token);
    return token;
  }

  static Future<void> syncToken(String? token) async {
    apiClient.token = token;
  }
}
