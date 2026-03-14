import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../services/playback_service.dart';

class MediaDetailScreen extends StatefulWidget {
  const MediaDetailScreen({super.key, required this.mediaId});

  final int mediaId;

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  bool _loading = true;
  String? _error;
  MediaItem? _item;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await MediaService.detail(widget.mediaId);
      final progress = await PlaybackService.getProgress(widget.mediaId);
      setState(() {
        _item = item;
        _progress = progress;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('媒体详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : _item == null
                  ? const Center(child: Text('未找到媒体'))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              PlaybackService.posterUrl(_item!.id),
                              height: 220,
                              fit: BoxFit.cover,
                              headers: {
                                if (apiClient.token?.isNotEmpty == true)
                                  'Authorization': 'Bearer ${apiClient.token}',
                              },
                              errorBuilder: (_, err, stack) => Container(
                                height: 220,
                                color: Colors.grey.shade900,
                                alignment: Alignment.center,
                                child: const Icon(Icons.movie, size: 48),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(_item!.title, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text('已播放：${_progress}s'),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => context.push('/player/${_item!.id}?title=${Uri.encodeComponent(_item!.title)}'),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('继续播放'),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
