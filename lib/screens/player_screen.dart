import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../core/api_client.dart';
import '../services/playback_service.dart';
import '../services/user_action_service.dart';

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
  bool _favorite = false;
  bool _updatingFavorite = false;

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
      final favorite = await UserActionService.isFavorite(widget.mediaId);

      final subtitles = await _loadSubtitles(_subtitleLang);

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        allowFullScreen: false,
        allowMuting: true,
        allowPlaybackSpeedChanging: false,
        subtitle: Subtitles(subtitles),
        showSubtitles: true,
        customControls: _NativeOverlayControls(
          onSubtitlePressed: _showSubtitleMenu,
          onAudioTrackPressed: _showAudioTrackMenu,
          onFullscreenPressed: _openFullscreen,
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
        _favorite = favorite;
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

  Future<void> _showSubtitleMenu() async {
    final lang = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('中文字幕'),
              subtitle: const Text('zh'),
              trailing: const Icon(Icons.subtitles),
              onTap: () => Navigator.pop(ctx, 'zh'),
            ),
            ListTile(
              title: const Text('English Subtitle'),
              subtitle: const Text('en'),
              trailing: const Icon(Icons.subtitles),
              onTap: () => Navigator.pop(ctx, 'en'),
            ),
            ListTile(
              title: const Text('日本語字幕'),
              subtitle: const Text('ja'),
              trailing: const Icon(Icons.subtitles),
              onTap: () => Navigator.pop(ctx, 'ja'),
            ),
          ],
        ),
      ),
    );
    if (lang == null) return;
    await _switchSubtitle(lang);
  }

  Future<void> _showAudioTrackMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => const SafeArea(
        child: ListTile(
          leading: Icon(Icons.audiotrack),
          title: Text('默认音轨'),
          subtitle: Text('当前版本仅单音轨占位，后续可接后端多音轨接口'),
        ),
      ),
    );
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
    vc.value.isPlaying ? vc.pause() : vc.play();
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
          onSubtitlePressed: _showSubtitleMenu,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    if (_updatingFavorite) return;
    final prev = _favorite;
    setState(() {
      _updatingFavorite = true;
      _favorite = !prev;
    });
    try {
      if (prev) {
        await UserActionService.removeFavorite(widget.mediaId);
      } else {
        await UserActionService.addFavorite(widget.mediaId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _favorite = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏操作失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _updatingFavorite = false);
    }
  }

  Future<void> _showFeedbackDialog() async {
    final controller = TextEditingController();
    final contactController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交反馈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(hintText: '请输入反馈内容'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contactController,
              decoration: const InputDecoration(hintText: '联系方式（选填）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('提交')),
        ],
      ),
    );
    if (ok != true) return;

    final content = controller.text.trim();
    if (content.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('反馈内容不能为空')));
      return;
    }

    try {
      await UserActionService.submitFeedback(
        mediaId: widget.mediaId,
        content: content,
        type: 'suggestion',
        contact: contactController.text.trim().isEmpty ? null : contactController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('反馈提交成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('反馈提交失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _share() async {
    final link = '${apiClient.baseUrl}/api/media/${widget.mediaId}/stream';
    await Clipboard.setData(ClipboardData(text: link));
    try {
      await UserActionService.share(widget.mediaId, channel: 'copy_link');
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
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
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('播放失败：$_error'))
              : chewie == null
                  ? const Center(child: Text('播放器初始化失败'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final topHeight = constraints.maxHeight / 3;
                        final bottomHeight = constraints.maxHeight * 2 / 3;
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
                                  if (vx > 150) _jumpBySeconds(10);
                                  if (vx < -150) _jumpBySeconds(-10);
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
                                    Text('简介', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                                    const SizedBox(height: 8),
                                    Text(
                                      '包含：进度、播放/暂停、音量、字幕、音轨、全屏。\n'
                                      '交互：双击暂停/播放，长按3x，左右滑动±10秒。',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        height: 1.6,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _updatingFavorite ? null : _toggleFavorite,
                                            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
                                            label: Text(_favorite ? '已收藏' : '收藏'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _showFeedbackDialog,
                                            icon: const Icon(Icons.feedback_outlined),
                                            label: const Text('反馈'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _share,
                                            icon: const Icon(Icons.share_outlined),
                                            label: const Text('分享'),
                                          ),
                                        ),
                                      ],
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

class _NativeOverlayControls extends StatefulWidget {
  const _NativeOverlayControls({
    required this.onSubtitlePressed,
    required this.onAudioTrackPressed,
    required this.onFullscreenPressed,
  });

  final VoidCallback onSubtitlePressed;
  final VoidCallback onAudioTrackPressed;
  final VoidCallback onFullscreenPressed;

  @override
  State<_NativeOverlayControls> createState() => _NativeOverlayControlsState();
}

class _NativeOverlayControlsState extends State<_NativeOverlayControls> {
  bool _visible = false;
  Timer? _timer;

  void _show() {
    _timer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = ChewieController.of(context);
    final vc = chewie.videoPlayerController;

    return MouseRegion(
      onHover: (_) => _show(),
      onEnter: (_) => _show(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: vc,
          builder: (context, value, _) {
            final durationMs = value.duration.inMilliseconds.toDouble();
            final positionMs = value.position.inMilliseconds.toDouble().clamp(0.0, durationMs <= 0 ? 1.0 : durationMs).toDouble();
            return Stack(
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _visible ? 1 : 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: !_visible,
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
                              value: durationMs <= 0 ? 0 : positionMs,
                              min: 0,
                              max: durationMs <= 0 ? 1 : durationMs,
                              onChanged: (v) => vc.seekTo(Duration(milliseconds: v.toInt())),
                            ),
                            LayoutBuilder(
                              builder: (context, box) {
                                final compact = box.maxWidth < 430;
                                final iconSize = compact ? 18.0 : 22.0;
                                final iconPadding = compact ? 2.0 : 6.0;
                                final volumeWidth = compact ? 54.0 : 80.0;

                                return Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => value.isPlaying ? vc.pause() : vc.play(),
                                      icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                      iconSize: iconSize,
                                      padding: EdgeInsets.all(iconPadding),
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${_fmt(value.position)} / ${_fmt(value.duration)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.volume_up, color: Colors.white70, size: 16),
                                    SizedBox(
                                      width: volumeWidth,
                                      child: Slider(
                                        value: value.volume,
                                        min: 0,
                                        max: 1,
                                        onChanged: (v) => vc.setVolume(v),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: widget.onSubtitlePressed,
                                      icon: const Icon(Icons.subtitles, color: Colors.white),
                                      iconSize: iconSize,
                                      padding: EdgeInsets.all(iconPadding),
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    ),
                                    IconButton(
                                      onPressed: widget.onFullscreenPressed,
                                      icon: const Icon(Icons.fullscreen, color: Colors.white),
                                      iconSize: iconSize,
                                      padding: EdgeInsets.all(iconPadding),
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FullscreenPlayerPage extends StatefulWidget {
  const _FullscreenPlayerPage({
    required this.title,
    required this.controller,
    required this.onJumpBySeconds,
    required this.onTogglePlayPause,
    required this.onLongPressFastForward,
    required this.onSubtitlePressed,
  });

  final String title;
  final VideoPlayerController controller;
  final Future<void> Function(int seconds) onJumpBySeconds;
  final VoidCallback onTogglePlayPause;
  final void Function(bool enable) onLongPressFastForward;
  final VoidCallback onSubtitlePressed;

  @override
  State<_FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<_FullscreenPlayerPage> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleAutoHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              onDoubleTap: widget.onTogglePlayPause,
              onLongPressStart: (_) => widget.onLongPressFastForward(true),
              onLongPressEnd: (_) => widget.onLongPressFastForward(false),
              onHorizontalDragEnd: (details) {
                final vx = details.primaryVelocity ?? 0;
                if (vx > 150) widget.onJumpBySeconds(10);
                if (vx < -150) widget.onJumpBySeconds(-10);
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: _controlsVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 56,
                    right: 56,
                    child: Center(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    left: 8,
                    right: 8,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) {
                        final durationMs = value.duration.inMilliseconds.toDouble();
                        final positionMs = value.position.inMilliseconds
                            .toDouble()
                            .clamp(0.0, durationMs <= 0 ? 1.0 : durationMs)
                            .toDouble();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Slider(
                                value: durationMs <= 0 ? 0 : positionMs,
                                min: 0,
                                max: durationMs <= 0 ? 1 : durationMs,
                                onChanged: (v) => widget.controller.seekTo(Duration(milliseconds: v.toInt())),
                              ),
                              LayoutBuilder(
                                builder: (context, box) {
                                  final compact = box.maxWidth < 700;
                                  final iconSize = compact ? 18.0 : 22.0;
                                  final iconPadding = compact ? 2.0 : 6.0;
                                  final volumeWidth = compact ? 76.0 : 96.0;

                                  return Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => value.isPlaying ? widget.controller.pause() : widget.controller.play(),
                                        icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                        iconSize: iconSize,
                                        padding: EdgeInsets.all(iconPadding),
                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_fmt(value.position)} / ${_fmt(value.duration)}',
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.volume_up, color: Colors.white70, size: 16),
                                      SizedBox(
                                        width: volumeWidth,
                                        child: Slider(
                                          value: value.volume,
                                          min: 0,
                                          max: 1,
                                          onChanged: (v) => widget.controller.setVolume(v),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: widget.onSubtitlePressed,
                                        icon: const Icon(Icons.subtitles, color: Colors.white),
                                        iconSize: iconSize,
                                        padding: EdgeInsets.all(iconPadding),
                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                                        iconSize: iconSize,
                                        padding: EdgeInsets.all(iconPadding),
                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
