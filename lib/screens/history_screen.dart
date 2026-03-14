import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../models/history_item.dart';
import '../services/playback_service.dart';
import '../services/user_action_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  List<HistoryItem> _items = [];
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
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 220) {
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
      final page = await UserActionService.history(page: 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.records;
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
      final page = await UserActionService.history(page: nextPage, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.records);
        _currentPage = nextPage;
        _hasMore = _items.length < page.total && page.records.isNotEmpty;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _formatDuration(int sec) {
    final d = Duration(seconds: sec);
    final hh = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [IconButton(onPressed: _loadInitial, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败：$_error'))
              : _items.isEmpty
                  ? const Center(child: Text('还没有历史记录'))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final item = _items[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => context.push('/player/${item.media.id}?title=${Uri.encodeComponent(item.media.title)}'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    PlaybackService.posterUrl(item.media.id),
                                    width: 100,
                                    height: 62,
                                    fit: BoxFit.cover,
                                    headers: {
                                      if (apiClient.token?.isNotEmpty == true)
                                        'Authorization': 'Bearer ${apiClient.token}',
                                    },
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 100,
                                      height: 62,
                                      color: Colors.grey.shade900,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(8),
                                      child: SvgPicture.asset('assets/logo.svg', fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.media.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '上次看到 ${_formatDuration(item.lastPositionSec)}',
                                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                    ),
    );
  }
}
