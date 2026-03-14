import '../core/api_client.dart';
import '../models/media_item.dart';
import '../models/page_result.dart';

class MediaService {
  static Future<PageResult<MediaItem>> list({int page = 1, int size = 20}) async {
    final data = await apiClient.get('/api/media?page=$page&size=$size') as Map<String, dynamic>;
    final records = ((data['records'] as List?) ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return PageResult(
      records: records,
      total: (data['total'] as num?)?.toInt() ?? records.length,
      current: (data['current'] as num?)?.toInt() ?? page,
    );
  }

  static Future<MediaItem> detail(int mediaId) async {
    final data = await apiClient.get('/api/media/$mediaId') as Map<String, dynamic>;
    return MediaItem.fromJson(data);
  }
}
