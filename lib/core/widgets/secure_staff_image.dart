import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'optimized_image.dart';

const _bucket = 'staff-checkins';
const _signedUrlTtl = Duration(hours: 1);

/// Re-sign a little before the link actually expires so a cached entry is
/// never handed out moments before it dies.
const _reuseWindow = Duration(minutes: 50);

class _SignedUrl {
  _SignedUrl(this.url) : _issuedAt = DateTime.now();

  final String url;
  final DateTime _issuedAt;

  bool get isFresh => DateTime.now().difference(_issuedAt) < _reuseWindow;
}

/// Signed URLs are cached by object path: the same avatar rendered in the
/// drawer, the account screen and a list must reuse one link, otherwise every
/// rebuild mints a new URL and `CachedNetworkImage` — which keys its cache on
/// the URL — re-downloads the image each time.
final Map<String, _SignedUrl> _urlCache = {};
final Map<String, Future<String?>> _inFlight = {};

Future<String?> _resolve(String? objectPath) {
  final value = objectPath?.trim();
  if (value == null || value.isEmpty) return Future.value(null);

  // Legacy rows still hold a full public URL; serve them until they are migrated.
  if (Uri.tryParse(value)?.hasScheme == true) return Future.value(value);

  final cached = _urlCache[value];
  if (cached != null && cached.isFresh) return Future.value(cached.url);

  return _inFlight[value] ??= _sign(value).whenComplete(() => _inFlight.remove(value));
}

Future<String?> _sign(String path) async {
  try {
    final url = await Supabase.instance.client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlTtl.inSeconds);
    _urlCache[path] = _SignedUrl(url);
    return url;
  } catch (e) {
    debugPrint('Signed URL notice for $path: $e');
    return null;
  }
}

/// Clears cached links. Call on sign-out so one staff member's photos are never
/// served from another's session.
void clearSecureStaffImageCache() {
  _urlCache.clear();
  _inFlight.clear();
}

/// Resolves a private `staff-checkins` object path to a short-lived URL.
/// Existing http(s) values are supported while older records are migrated.
class SecureStaffImage extends StatefulWidget {
  const SecureStaffImage({
    super.key,
    required this.objectPath,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String? objectPath;
  final double width;
  final double height;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<SecureStaffImage> createState() => _SecureStaffImageState();
}

class _SecureStaffImageState extends State<SecureStaffImage> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolve(widget.objectPath);
  }

  @override
  void didUpdateWidget(covariant SecureStaffImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.objectPath != widget.objectPath) {
      _url = _resolve(widget.objectPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return widget.fallback;
        return OptimizedImage(
          imageUrl: url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          memCacheWidth: (widget.width * 2).round(),
          memCacheHeight: (widget.height * 2).round(),
        );
      },
    );
  }
}
