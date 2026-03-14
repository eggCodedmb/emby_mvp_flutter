class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.durationSec,
    required this.posterUrl,
  });

  final int id;
  final String title;
  final int durationSec;
  final String? posterUrl;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '未命名',
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      posterUrl: json['posterUrl'] as String?,
    );
  }
}
