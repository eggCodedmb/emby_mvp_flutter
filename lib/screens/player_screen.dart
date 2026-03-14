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
        allowFullScreen: false,
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
      return isVtt ? _parseVtt(body) : _parseSrt(body);
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
    final cc = _chewieController;
    if (cc == null) return;

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

  void _setLongPressFastForward(bool enable) {
    final vc = _videoController;
    if (vc == null) return;
    _isLongPressing = enable;
    vc.setPlaybackSpeed(enable ? 3.0 : 1.0);
    setState(() {});
  }

  void _openFullscreen() {
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenPlayerPage(
          title: widget.title,
          controller: vc,
          onJumpBySeconds: _jumpBySeconds,
          onTogglePlayPause: _togglePlayPause,
          onLongPressFastForward: _setLongPressFastForward,
        ),
      ),
    );
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
    final vc = _videoController;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('播放失败：$_error'))
              : chewie == null || vc == null
                  ? const Center(child: Text('播放器初始化失败'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final topHeight = constraints.maxHeight / 3;
                        final bottomHeight = constraints.maxHeight * 2 / 3;
                        final position = vc.value.position;
                        final duration = vc.value.duration;

                        return Column(
                          children: [
                            SizedBox(
                              height: topHeight,
                              width: double.infinity,
                              child: GestureDetector(
                                onDoubleTap: _togglePlayPause,
                                onLongPressStart: (_) => _setLongPressFastForward(true),
                                onLongPressEnd: (_) => _setLongPressFastForward(false),
                                onHorizontalDragEnd: (details) {
                                  final vx = details.primaryVelocity ?? 0;
                                  if (vx > 150) {
                                    _jumpBySeconds(10);
                                  } else if (vx < -150) {
                                    _jumpBySeconds(-10);
                                  }
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Chewie(controller: chewie),
                                    Positioned(
                                      right: 10,
                                      top: 10,
                                      child: IconButton.filledTonal(
                                        onPressed: _openFullscreen,
                                        icon: const Icon(Icons.fullscreen),
                                      ),
                                    ),
                                    if (_isLongPressing)
                                      Positioned(
                                        right: 12,
                                        top: 56,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text('3.0x 快进中', style: TextStyle(color: Colors.white)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: bottomHeight,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
                                    const SizedBox(height: 10),
                                    Text(
                                      '媒体ID：${widget.mediaId}  ·  进度：${_formatTime(position)} / ${_formatTime(duration)}',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _togglePlayPause,
                                          icon: Icon(vc.value.isPlaying ? Icons.pause : Icons.play_arrow),
                                          label: Text(vc.value.isPlaying ? '暂停' : '播放'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _jumpBySeconds(-10),
                                          icon: const Icon(Icons.replay_10),
                                          label: const Text('后退10秒'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _jumpBySeconds(10),
                                          icon: const Icon(Icons.forward_10),
                                          label: const Text('前进10秒'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _openFullscreen,
                                          icon: const Icon(Icons.fullscreen),
                                          label: const Text('全屏'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('字幕切换', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 10,
                                      children: [
                                        ChoiceChip(
                                          label: const Text('中文'),
                                          selected: _subtitleLang == 'zh',
                                          onSelected: (_) => _switchSubtitle('zh'),
                                        ),
                                        ChoiceChip(
                                          label: const Text('English'),
                                          selected: _subtitleLang == 'en',
                                          onSelected: (_) => _switchSubtitle('en'),
                                        ),
                                        ChoiceChip(
                                          label: const Text('日本語'),
                                          selected: _subtitleLang == 'ja',
                                          onSelected: (_) => _switchSubtitle('ja'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('简介', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '手势说明：双击暂停/播放，长按3x快进，左右滑动快退/快进10秒。\n'
                                      '本页布局：视频区占上方 1/3，简介与操作区占下方 2/3。\n'
                                      '全屏模式下同样支持手势操作。',
                                      style: TextStyle(color: Colors.white70, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
    );
  }
}

class _FullscreenPlayerPage extends StatelessWidget {
  const _FullscreenPlayerPage({
    required this.title,
    required this.controller,
    required this.onJumpBySeconds,
    required this.onTogglePlayPause,
    required this.onLongPressFastForward,
  });

  final String title;
  final VideoPlayerController controller;
  final Future<void> Function(int seconds) onJumpBySeconds;
  final VoidCallback onTogglePlayPause;
  final void Function(bool enable) onLongPressFastForward;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: onTogglePlayPause,
                onLongPressStart: (_) => onLongPressFastForward(true),
                onLongPressEnd: (_) => onLongPressFastForward(false),
                onHorizontalDragEnd: (details) {
                  final vx = details.primaryVelocity ?? 0;
                  if (vx > 150) {
                    onJumpBySeconds(10);
                  } else if (vx < -150) {
                    onJumpBySeconds(-10);
                  }
                },
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '全屏手势：双击暂停/播放｜长按3x快进｜左右滑动±10秒',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
