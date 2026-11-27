import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_controller.dart';

final profileImageCacheProvider = Provider((ref) {
  ref.watch(authControllerProvider.select((state) => state.session?.userId));
  final cache = ProfileImageCache();
  ref.onDispose(cache.clear);
  return cache;
});

class _ImageEntry {
  _ImageEntry(this.url, this.until);
  final String url;
  final DateTime until;
  final providers = <ImageProvider>{};
}

/// Account-scoped, bounded memory cache. Nothing is written to disk.
class ProfileImageCache {
  ProfileImageCache({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _entries = <String, _ImageEntry>{};

  static String identity(String url) {
    final uri = Uri.parse(url);
    final parameters = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) {
        final lower = key.toLowerCase();
        return lower.startsWith('x-amz-') ||
            const {'awsaccesskeyid', 'signature', 'expires'}.contains(lower);
      });
    return uri
        .replace(
          queryParameters: parameters.isEmpty ? null : parameters,
          query: parameters.isEmpty ? '' : null,
          fragment: '',
        )
        .toString();
  }

  String resolve(String url) {
    final key = identity(url);
    final now = _now().toUtc();
    final old = _entries.remove(key);
    if (old != null && now.isBefore(old.until)) {
      _entries[key] = old;
      return old.url;
    }
    if (old != null) _evict(old);
    var until = now.add(const Duration(minutes: 3));
    final query = Uri.parse(url).queryParameters;
    final date = query['X-Amz-Date'];
    final seconds = int.tryParse(query['X-Amz-Expires'] ?? '');
    if (date != null && seconds != null && date.length == 16) {
      final issued = DateTime.tryParse(
        '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}T${date.substring(9, 11)}:${date.substring(11, 13)}:${date.substring(13, 15)}Z',
      );
      if (issued != null) {
        final expires = issued.add(Duration(seconds: seconds - 20));
        if (expires.isBefore(until)) until = expires;
      }
    }
    _entries[key] = _ImageEntry(url, until);
    while (_entries.length > 64) {
      _evict(_entries.remove(_entries.keys.first)!);
    }
    return url;
  }

  ImageProvider image(String url, int size) {
    final resolved = resolve(url);
    final provider = ResizeImage.resizeIfNeeded(
      size,
      null,
      NetworkImage(resolved),
    );
    _entries[identity(url)]!.providers.add(provider);
    return provider;
  }

  void remove(String url) {
    final entry = _entries.remove(identity(url));
    if (entry != null) _evict(entry);
  }

  void clear() {
    for (final entry in _entries.values) {
      _evict(entry);
    }
    _entries.clear();
  }

  void _evict(_ImageEntry entry) {
    for (final provider in entry.providers) {
      unawaited(provider.evict());
    }
  }
}

class ProfileImage extends ConsumerWidget {
  const ProfileImage(
    this.url, {
    this.decodeSize = 512,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });
  final String url;
  final int decodeSize;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(profileImageCacheProvider);
    final owner = ref.watch(
      authControllerProvider.select((s) => s.session?.userId),
    );
    return Image(
      // Preserve decoded pixels while the URL lease rotates for this same
      // account and asset. A different asset/account gets a fresh Image state.
      key: ValueKey((owner, ProfileImageCache.identity(url), decodeSize)),
      gaplessPlayback: true,
      image: cache.image(url, decodeSize),
      fit: fit,
      errorBuilder: (_, _, _) {
        cache.remove(url);
        return fallback;
      },
    );
  }
}
