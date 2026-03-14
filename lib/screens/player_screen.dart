import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/api_client.dart';
import '../services/playback_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.mediaId, required this.title});

  final int mediaId;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(PlaybackService.streamUrl(widget.mediaId)),
        httpHeaders: {
          if (apiClient.token?.isNotEmpty == true) 'Authorization': 'Bearer ${apiClient.token}',
        },
      );
      await controller.initialize();

      final sec = await PlaybackService.getProgress(widget.mediaId);
      if (sec > 0) {
        await controller.seekTo(Duration(seconds: sec));
      }
      await controller.play();

      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        final pos = controller.value.position.inSeconds;
        await PlaybackService.saveProgress(widget.mediaId, pos);
      });

      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    final pos = _controller?.value.position.inSeconds ?? 0;
    PlaybackService.saveProgress(widget.mediaId, pos);
    _saveTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('播放失败：$_error'))
              : controller == null
                  ? const Center(child: Text('播放器初始化失败'))
                  : Column(
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        VideoProgressIndicator(controller, allowScrubbing: true),
                        Wrap(
                          spacing: 12,
                          children: [
                            IconButton(
                              onPressed: () => controller.value.isPlaying ? controller.pause() : controller.play(),
                              icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                            ),
                            OutlinedButton(
                              onPressed: () => controller.setPlaybackSpeed(1.0),
                              child: const Text('1.0x'),
                            ),
                            OutlinedButton(
                              onPressed: () => controller.setPlaybackSpeed(1.5),
                              child: const Text('1.5x'),
                            ),
                            OutlinedButton(
                              onPressed: () => controller.setPlaybackSpeed(2.0),
                              child: const Text('2.0x'),
                            ),
                          ],
                        ),
                      ],
                    ),
    );
  }
}
