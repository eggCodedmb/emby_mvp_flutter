import '../core/api_client.dart';
import '../models/history_item.dart';
import '../models/media_item.dart';
import '../models/page_result.dart';

class UserActionService {
  static Future<bool> isFavorite(int mediaId) async {
    final data = await apiClient.get('/api/user/favorites/$mediaId/exists') as Map<String, dynamic>;
    return data['favorite'] == true;
  }

  static Future<void> addFavorite(int mediaId) async {
    await apiClient.post('/api/user/favorites/$mediaId');
  }

  static Future<void> removeFavorite(int mediaId) async {
    await apiClient.delete('/api/user/favorites/$mediaId');
  }

  static Future<PageResult<MediaItem>> favorites({int page = 1, int size = 20}) async {
    final data = await apiClient.get('/api/user/favorites?page=$page&size=$size') as Map<String, dynamic>;
    final records = ((data['records'] as List?) ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return PageResult(
      records: records,
      total: (data['total'] as num?)?.toInt() ?? records.length,
      current: (data['current'] as num?)?.toInt() ?? page,
    );
  }

  static Future<PageResult<HistoryItem>> history({int page = 1, int size = 20}) async {
    final data = await apiClient.get('/api/user/history?page=$page&size=$size') as Map<String, dynamic>;
    final records = ((data['records'] as List?) ?? [])
        .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return PageResult(
      records: records,
      total: (data['total'] as num?)?.toInt() ?? records.length,
      current: (data['current'] as num?)?.toInt() ?? page,
    );
  }

  static Future<void> submitFeedback({required String content, int? mediaId, String type = 'other', String? contact}) async {
    await apiClient.post('/api/user/feedback', body: {
      'content': content,
      'mediaId': mediaId,
      'type': type,
      'contact': contact,
    });
  }

  static Future<void> share(int mediaId, {String channel = 'copy_link'}) async {
    await apiClient.post('/api/user/share/$mediaId', body: {'channel': channel});
  }
}
