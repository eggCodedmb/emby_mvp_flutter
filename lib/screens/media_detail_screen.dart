import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../services/playback_service.dart';
import '../services/user_action_service.dart';

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
  bool _favorite = false;
  bool _updatingFavorite = false;

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
      final favorite = await UserActionService.isFavorite(widget.mediaId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _progress = progress;
        _favorite = favorite;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_updatingFavorite || _item == null) return;
    setState(() => _updatingFavorite = true);
    final prev = _favorite;
    setState(() => _favorite = !_favorite);
    try {
      if (prev) {
        await UserActionService.removeFavorite(_item!.id);
      } else {
        await UserActionService.addFavorite(_item!.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _favorite = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _updatingFavorite = false);
    }
  }

  Future<void> _showFeedbackDialog() async {
    final controller = TextEditingController();
    final contactController = TextEditingController();
    final result = await showDialog<bool>(
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
              decoration: const InputDecoration(hintText: '请输入你的反馈内容'),
            ),
            const SizedBox(height: 12),
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

    if (result != true) return;
    final content = controller.text.trim();
    final contact = contactController.text.trim();
    if (content.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('反馈内容不能为空')));
      return;
    }

    try {
      await UserActionService.submitFeedback(
        content: content,
        mediaId: _item?.id,
        type: 'suggestion',
        contact: contact.isEmpty ? null : contact,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('反馈已提交')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _share() async {
    if (_item == null) return;
    final link = '${apiClient.baseUrl}/api/media/${_item!.id}/stream';
    await Clipboard.setData(ClipboardData(text: link));
    try {
      await UserActionService.share(_item!.id);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('播放链接已复制')));
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
                                padding: const EdgeInsets.all(28),
                                child: SvgPicture.asset('assets/logo.svg', fit: BoxFit.contain),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(_item!.title, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text('已播放：${_progress}s'),
                          const SizedBox(height: 16),
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
