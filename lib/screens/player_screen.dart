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
  Timer? _controlsHideTimer;
  bool _controlsVisible = false;
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
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.redAccent,
          bufferedColor: Colors.white30,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
        ),
      );

      videoController.addListener(() {
        if (mounted) setState(() {});
      });

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

  void _showControls({bool autoHide = true}) {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (autoHide) {
      _controlsHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
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
    final clamped = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
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
    _showControls();
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
    _controlsHideTimer?.cancel();
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
                        final positionMs = vc.value.position.inMilliseconds.toDouble();
                        final durationMs = vc.value.duration.inMilliseconds.toDouble();

                        return Column(
                          children: [
                            SizedBox(
                              height: topHeight,
                              width: double.infinity,
                              child: MouseRegion(
                                onEnter: (_) => _showControls(),
                                onHover: (_) => _showControls(),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showControls(),
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
                                      if (_isLongPressing)
                                        Positioned(
                                          right: 12,
                                          top: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                                            child: const Text('3.0x 快进中', style: TextStyle(color: Colors.white)),
                                          ),
                                        ),
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 180),
                                        opacity: _controlsVisible ? 1 : 0,
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: IgnorePointer(
                                            ignoring: !_controlsVisible,
                                            child: Container(
                                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                              decoration: const BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [Colors.transparent, Color(0xCC000000)],
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Slider(
                                                    value: durationMs <= 0 ? 0 : positionMs.clamp(0, durationMs),
                                                    min: 0,
                                                    max: durationMs <= 0 ? 1 : durationMs,
                                                    onChanged: (v) => vc.seekTo(Duration(milliseconds: v.toInt())),
                                                  ),
                                                  Row(
                                                    children: [
                                                      IconButton(
                                                        onPressed: _togglePlayPause,
                                                        icon: Icon(vc.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                                      ),
                                                      Text(
                                                        '${_formatTime(vc.value.position)} / ${_formatTime(vc.value.duration)}',
                                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                                      ),
                                                      const Spacer(),
                                                      const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                                                      SizedBox(
                                                        width: 90,
                                                        child: Slider(
                                                          value: vc.value.volume,
                                                          min: 0,
                                                          max: 1,
                                                          onChanged: (v) => vc.setVolume(v),
                                                        ),
                                                      ),
                                                      PopupMenuButton<String>(
                                                        tooltip: '字幕',
                                                        onSelected: _switchSubtitle,
                                                        itemBuilder: (_) => const [
                                                          PopupMenuItem(value: 'zh', child: Text('中文字幕')),
                                                          PopupMenuItem(value: 'en', child: Text('English')),
                                                          PopupMenuItem(value: 'ja', child: Text('日本語')),
                                                        ],
                                                        icon: const Icon(Icons.subtitles, color: Colors.white),
                                                      ),
                                                      PopupMenuButton<String>(
                                                        tooltip: '音轨',
                                                        onSelected: (_) {},
                                                        itemBuilder: (_) => const [
                                                          PopupMenuItem(value: 'default', child: Text('默认音轨')),
                                                        ],
                                                        icon: const Icon(Icons.audiotrack, color: Colors.white),
                                                      ),
                                                      IconButton(
                                                        onPressed: _openFullscreen,
                                                        icon: const Icon(Icons.fullscreen, color: Colors.white),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                      '媒体ID：${widget.mediaId}',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('简介', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '控制栏已改为画面底部边缘悬浮，默认隐藏；鼠标悬停或点击视频时显示。\n'
                                      '手势：双击暂停/播放，长按3x快进，左右滑动±10秒。\n'
                                      '上方视频占1/3，下方简介占2/3。',
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
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '$title\n全屏手势：双击暂停/播放｜长按3x快进｜左右滑动±10秒',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
