import '../core/api_client.dart';

class PlaybackService {
  static Future<int> getProgress(int mediaId) async {
    final data = await apiClient.get('/api/playback/$mediaId/progress') as Map<String, dynamic>;
    return (data['positionSec'] as num?)?.toInt() ?? 0;
  }

  static Future<void> saveProgress(int mediaId, int positionSec) async {
    await apiClient.post('/api/playback/$mediaId/progress', body: {
      'positionSec': positionSec,
    });

    // 同步写入“历史记录”新接口（失败不影响主播放进度）
    try {
      await apiClient.put('/api/user/history/$mediaId', body: {
        'lastPositionSec': positionSec,
      });
    } catch (_) {}
  }

  static String streamUrl(int mediaId) => '${apiClient.baseUrl}/api/media/$mediaId/stream';

  static String posterUrl(int mediaId) => '${apiClient.baseUrl}/api/media/$mediaId/poster';

  static String subtitleUrl(int mediaId, {required String lang, String? title}) {
    final q = <String, String>{'lang': lang, if (title?.isNotEmpty == true) 'title': title!};
    final uri = Uri.parse('${apiClient.baseUrl}/api/media/$mediaId/subtitle').replace(queryParameters: q);
    return uri.toString();
  }
}
