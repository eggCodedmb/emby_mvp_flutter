import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      setState(() => _items = page.records);
    } catch (e) {
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
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _items[i];
                    final duration = Duration(seconds: m.durationSec);
                    final mm = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
                    final ss = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          PlaybackService.posterUrl(m.id),
                          width: 80,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, err, stack) => Container(
                            width: 80,
                            height: 48,
                            color: Colors.grey.shade900,
                            alignment: Alignment.center,
                            child: const Icon(Icons.movie_outlined),
                          ),
                        ),
                      ),
                      title: Text(m.title),
                      subtitle: Text('时长 $mm:$ss'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/media/${m.id}'),
                    );
                  },
                ),
    );
  }
}
