import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;
  String _subtitleLang = 'zh';
  bool _isLongPressing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final videoController = VideoPlayerController.networkUrl(
        Uri.parse(PlaybackService.streamUrl(widget.mediaId)),
        httpHeaders: {
          if (apiClient.token?.isNotEmpty == true) 'Authorization': 'Bearer ${apiClient.token}',
        },
      );

      await videoController.initialize();
      final sec = await PlaybackService.getProgress(widget.mediaId);
      if (sec > 0) {
        await videoController.seekTo(Duration(seconds: sec));
      }

      final subtitles = await _loadSubtitles(_subtitleLang);

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        subtitle: Subtitles(subtitles),
        showSubtitles: true,
        subtitleBuilder: (context, text) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.black54,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
          ),
        ),
      );

      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        final pos = videoController.value.position.inSeconds;
        await PlaybackService.saveProgress(widget.mediaId, pos);
      });

      if (!mounted) return;
      setState(() {
        _videoController = videoController;
        _chewieController = chewieController;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<Subtitle>> _loadSubtitles(String lang) async {
    try {
      final resp = await http.get(
        Uri.parse(PlaybackService.subtitleUrl(widget.mediaId, lang: lang, title: widget.title)),
        headers: {
          if (apiClient.token?.isNotEmpty == true) 'Authorization': 'Bearer ${apiClient.token}',
        },
      );
      if (resp.statusCode >= 400 || resp.body.trim().isEmpty) return const [];

      final body = resp.body;
      final isVtt = (resp.headers['content-type'] ?? '').contains('text/vtt') || body.trimLeft().startsWith('WEBVTT');
      final items = isVtt ? _parseVtt(body) : _parseSrt(body);
      return items;
    } catch (_) {
      return const [];
    }
  }

  List<Subtitle> _parseSrt(String source) {
    final text = source.replaceAll('\r\n', '\n');
    final blocks = text.split('\n\n');
    final results = <Subtitle>[];

    for (final block in blocks) {
      final lines = block.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.length < 2) continue;
      final timeLine = lines.firstWhere((l) => l.contains('-->'), orElse: () => '');
      if (timeLine.isEmpty) continue;
      final parts = timeLine.split('-->');
      if (parts.length != 2) continue;
      final start = _parseSrtTime(parts[0].trim());
      final end = _parseSrtTime(parts[1].trim());
      if (start == null || end == null) continue;
      final content = lines.skipWhile((l) => !l.contains('-->')).skip(1).join('\n');
      results.add(Subtitle(index: results.length, start: start, end: end, text: content));
    }

    return results;
  }

  Duration? _parseSrtTime(String s) {
    final reg = RegExp(r'^(\d{2}):(\d{2}):(\d{2})[,.](\d{3})');
    final m = reg.firstMatch(s);
    if (m == null) return null;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
      milliseconds: int.parse(m.group(4)!),
    );
  }

  List<Subtitle> _parseVtt(String source) {
    final text = source.replaceAll('\r\n', '\n').replaceAll('WEBVTT', '').trim();
    final blocks = text.split('\n\n');
    final results = <Subtitle>[];

    for (final block in blocks) {
      final lines = block.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final timeLine = lines.firstWhere((l) => l.contains('-->'), orElse: () => '');
      if (timeLine.isEmpty) continue;
      final parts = timeLine.split('-->');
      if (parts.length != 2) continue;
      final start = _parseVttTime(parts[0].trim());
      final end = _parseVttTime(parts[1].trim().split(' ').first);
      if (start == null || end == null) continue;
      final content = lines.skipWhile((l) => !l.contains('-->')).skip(1).join('\n');
      results.add(Subtitle(index: results.length, start: start, end: end, text: content));
    }

    return results;
  }

  Duration? _parseVttTime(String s) {
    final reg = RegExp(r'^(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})');
    final m = reg.firstMatch(s);
    if (m == null) return null;
    return Duration(
      hours: int.tryParse(m.group(1) ?? '0') ?? 0,
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
      milliseconds: int.parse(m.group(4)!),
    );
  }

  Future<void> _switchSubtitle(String lang) async {
    final vc = _videoController;
    final cc = _chewieController;
    if (vc == null || cc == null) return;

    setState(() => _subtitleLang = lang);
    final subs = await _loadSubtitles(lang);
    cc.setSubtitle(subs);
    if (mounted) setState(() {});
  }

  Future<void> _jumpBySeconds(int seconds) async {
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;
    final current = vc.value.position;
    final target = current + Duration(seconds: seconds);
    final duration = vc.value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    await vc.seekTo(clamped);
  }

  void _togglePlayPause() {
    final vc = _videoController;
    if (vc == null) return;
    if (vc.value.isPlaying) {
      vc.pause();
    } else {
      vc.play();
    }
    setState(() {});
  }

  @override
  void dispose() {
    final pos = _videoController?.value.position.inSeconds ?? 0;
    PlaybackService.saveProgress(widget.mediaId, pos);
    _saveTimer?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewieController;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            initialValue: _subtitleLang,
            onSelected: _switchSubtitle,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'zh', child: Text('中文字幕')),
              PopupMenuItem(value: 'en', child: Text('English Subtitle')),
              PopupMenuItem(value: 'ja', child: Text('日本語字幕')),
            ],
            icon: const Icon(Icons.subtitles_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('播放失败：$_error'))
              : chewie == null
                  ? const Center(child: Text('播放器初始化失败'))
                  : Column(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onDoubleTap: _togglePlayPause,
                            onLongPressStart: (_) {
                              final vc = _videoController;
                              if (vc == null) return;
                              _isLongPressing = true;
                              vc.setPlaybackSpeed(3.0);
                              setState(() {});
                            },
                            onLongPressEnd: (_) {
                              final vc = _videoController;
                              if (vc == null) return;
                              _isLongPressing = false;
                              vc.setPlaybackSpeed(1.0);
                              setState(() {});
                            },
                            onHorizontalDragEnd: (details) {
                              final vx = details.primaryVelocity ?? 0;
                              if (vx > 150) {
                                _jumpBySeconds(10);
                              } else if (vx < -150) {
                                _jumpBySeconds(-10);
                              }
                            },
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                Chewie(controller: chewie),
                                if (_isLongPressing)
                                  Container(
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text('3.0x 快进中', style: TextStyle(color: Colors.white)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          color: Colors.black26,
                          child: const Text(
                            '手势：双击暂停/播放｜长按3x快进｜左右滑动快退/快进10秒｜支持全屏',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
