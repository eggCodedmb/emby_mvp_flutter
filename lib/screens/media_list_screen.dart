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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _loading = true;
  bool _searching = false;
  String _keyword = '';
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
    _searchController.dispose();
    _searchFocusNode.dispose();
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
      final page = await MediaService.list(page: 1, size: _pageSize, keyword: _keyword);
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
      final page = await MediaService.list(page: nextPage, size: _pageSize, keyword: _keyword);
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

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        if (_keyword.isNotEmpty) {
          _keyword = '';
          _loadInitial();
        }
      }
    });
    if (_searching) {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _searchFocusNode.requestFocus();
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _submitSearch(String value) {
    final kw = value.trim();
    if (kw == _keyword) return;
    setState(() => _keyword = kw);
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        titleSpacing: 8,
        leadingWidth: _searching ? 56 : 48,
        leading: IconButton(
          onPressed: _toggleSearch,
          icon: Icon(_searching ? Icons.close : Icons.search),
        ),
        title: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: _searching ? 46 : 36,
          alignment: Alignment.centerLeft,
          child: _searching
              ? TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submitSearch,
                  decoration: InputDecoration(
                    hintText: '搜索媒体标题',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _submitSearch('');
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear, size: 18),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : const Text('媒体库'),
        ),
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
