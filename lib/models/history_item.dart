import 'media_item.dart';

class HistoryItem {
  const HistoryItem({
    required this.media,
    required this.lastPositionSec,
    required this.durationSec,
    required this.updatedAt,
  });

  final MediaItem media;
  final int lastPositionSec;
  final int? durationSec;
  final DateTime? updatedAt;

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      media: MediaItem.fromJson(json['media'] as Map<String, dynamic>),
      lastPositionSec: (json['lastPositionSec'] as num?)?.toInt() ?? 0,
      durationSec: (json['durationSec'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] == null ? null : DateTime.tryParse(json['updatedAt'].toString()),
    );
  }
}
