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
  }

  static String streamUrl(int mediaId) => '${apiClient.baseUrl}/api/media/$mediaId/stream';
  static String posterUrl(int mediaId) => '${apiClient.baseUrl}/api/media/$mediaId/poster';
}
