import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';

import '../models/media_item.dart';
import '../services/media_service.dart';
import '../services/playback_service.dart';

class MediaListScreen extends StatefulWidget {
  const MediaListScreen({super.key});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  List<MediaItem> _items = [];
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = true;
    });
    try {
      final page = await MediaService.list(page: 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.records;
        _currentPage = 1;
        _hasMore = _items.length < page.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final page = await MediaService.list(page: nextPage, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.records);
        _currentPage = nextPage;
        _hasMore = _items.length < page.total && page.records.isNotEmpty;
      });
    } catch (_) {
      // 滚动加载失败先静默，避免频繁打断
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.70)),
          ),
        ),
        actions: [
          IconButton(onPressed: _loadInitial, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = max(2, (constraints.maxWidth / 190).floor());
                    return GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 8),
                                Text('加载中...', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }

                        final m = _items[i];
                        final duration = Duration(seconds: m.durationSec);
                        final hh = duration.inHours;
                        final mm = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
                        final ss = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
                        final durationText = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push('/player/${m.id}?title=${Uri.encodeComponent(m.title)}'),
                          child: Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Image.network(
                                      PlaybackService.posterUrl(m.id),
                                      fit: BoxFit.cover,
                                      headers: {
                                        if (apiClient.token?.isNotEmpty == true)
                                          'Authorization': 'Bearer ${apiClient.token}',
                                      },
                                      errorBuilder: (_, err, stack) => Container(
                                        color: Colors.grey.shade900,
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(18),
                                        child: SvgPicture.asset(
                                          'assets/logo.svg',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '时长 $durationText',
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
