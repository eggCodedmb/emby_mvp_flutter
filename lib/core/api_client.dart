import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  String? token;

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path'), headers: _headers(json: false));
    return _unwrap(resp);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _unwrap(resp);
  }

  Future<dynamic> put(String path, {required Object body}) async {
    final resp = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _unwrap(resp);
  }

  Future<dynamic> delete(String path) async {
    final resp = await http.delete(Uri.parse('$baseUrl$path'), headers: _headers());
    return _unwrap(resp);
  }

  dynamic _unwrap(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('无效响应: ${resp.body}');
    }
    if (resp.statusCode >= 400) {
      throw Exception(decoded['message'] ?? 'HTTP ${resp.statusCode}');
    }
    final code = decoded['code'] as int? ?? -1;
    if (code != 0) {
      throw Exception(decoded['message'] ?? '请求失败(code=$code)');
    }
    return decoded['data'];
  }
}

final apiClient = ApiClient(baseUrl: 'http://10.0.2.2:8080');
