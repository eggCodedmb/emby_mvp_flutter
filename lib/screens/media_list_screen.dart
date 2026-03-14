import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/auth_store.dart';
import '../models/media_item.dart';
import '../services/media_service.dart';
import '../services/playback_service.dart';

class MediaListScreen extends StatefulWidget {
  const MediaListScreen({super.key});

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  bool _loading = true;
  String? _error;
  List<MediaItem> _items = [];

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
      final page = await MediaService.list();
      if (!mounted) return;
      setState(() => _items = page.records);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => context.read<AuthStore>().logout(),
            icon: const Icon(Icons.logout),
          ),
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
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final m = _items[i];
                        final duration = Duration(seconds: m.durationSec);
                        final hh = duration.inHours;
                        final mm = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
                        final ss = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
                        final durationText = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.push('/media/${m.id}'),
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
                                        child: const Icon(Icons.movie_outlined, size: 36),
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
