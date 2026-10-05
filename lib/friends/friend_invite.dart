import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendInviteLink {
  /// Configure only after the landing page has been published and verified.
  static const baseUrl = String.fromEnvironment('FRIEND_INVITE_BASE_URL');
  static const shortCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static final _shortCode = RegExp(r'^[A-HJKMNP-Z2-9]{8}$');
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Uri? get publicBase => _publicBase(baseUrl);
  static bool get supportsPublicLinks => publicBase != null;

  static Uri? _publicBase(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            RegExp(r'^/[A-Za-z0-9/_-]*$|^$').hasMatch(uri.path) &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            !uri.pathSegments.any((part) => part == '.' || part == '..')
        ? uri
        : null;
  }

  static String? normalizeCode(String value) {
    final text = value.trim();
    if (_uuid.hasMatch(text)) return text.toLowerCase();
    final upper = text.toUpperCase();
    final compact =
        RegExp(r'^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$').hasMatch(upper)
        ? upper.replaceAll('-', '')
        : upper;
    return _shortCode.hasMatch(compact) ? compact : null;
  }

  static String? parse(String input, {String? configuredBaseUrl}) {
    final text = input.trim();
    final direct = normalizeCode(text);
    if (direct != null) return direct;
    if (text.contains('%')) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    if (uri.scheme == 'setkeep' &&
        uri.host == 'friend-invite' &&
        !uri.hasPort &&
        !uri.hasQuery &&
        uri.pathSegments.length == 1 &&
        uri.path == '/${uri.pathSegments.single}') {
      return normalizeCode(uri.pathSegments.single);
    }
    final base = _publicBase(configuredBaseUrl ?? baseUrl);
    if (base == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.origin != base.origin) {
      return null;
    }
    final path = base.path.replaceFirst(RegExp(r'/$'), '');
    // Static hosting serves invite.html at /invite; the code stays in a query.
    if (uri.path == path && uri.hasQuery) {
      final parameters = uri.queryParametersAll;
      if (parameters.length != 1 ||
          parameters['code']?.length != 1 ||
          !RegExp(r'^code=[A-Za-z0-9-]+$').hasMatch(uri.query)) {
        return null;
      }
      return normalizeCode(parameters['code']!.single);
    }
    // Previously issued HTTPS links may have a UUID as their last path segment.
    final prefix = '$path/';
    if (uri.hasQuery || !uri.path.startsWith(prefix)) return null;
    return normalizeCode(uri.path.substring(prefix.length));
  }

  static String url(String code, {String? configuredBaseUrl}) {
    final normalized = normalizeCode(code);
    if (normalized == null) throw ArgumentError('Invalid invite');
    final base = _publicBase(configuredBaseUrl ?? baseUrl);
    return base == null
        ? 'setkeep://friend-invite/$normalized'
        : base
              .replace(
                path: base.path.replaceFirst(RegExp(r'/$'), ''),
                queryParameters: {'code': normalized},
              )
              .toString();
  }
}

/// Capture before login. Only explicit successful handling consumes an invite.
class FriendInviteStore {
  static final pending = ValueNotifier<String?>(null);

  /// Also signals receiving the same invite again after dismissing its preview.
  static final revision = ValueNotifier<int>(0);
  static const _key = 'pending_friend_invite';
  static Future<void>? _started;
  static Future<void>? _writes;
  static StreamSubscription<Uri>? _subscription;

  static Future<void> _serialize(Future<void> Function() action) async {
    final previous = _writes;
    final operation = previous == null
        ? action()
        : previous.then((_) => action());
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _writes = tail;
    try {
      await operation;
    } finally {
      // Complete the serial tail before returning to a widget's caller/zone.
      await tail;
      if (identical(_writes, tail)) _writes = null;
    }
  }

  static Future<void> start() => _started ??= _start();
  static Future<void> _start() async {
    await _serialize(() async {
      final preferences = await SharedPreferences.getInstance();
      final restored = FriendInviteLink.normalizeCode(
        preferences.getString(_key) ?? '',
      );
      if (restored != null) {
        pending.value = restored;
        revision.value++;
      }
    });
    try {
      final links = AppLinks();
      final initialRevision = revision.value;
      _subscription = links.uriLinkStream.listen(
        (uri) => unawaited(capture(uri.toString())),
        onError: (Object _) {},
      );
      final initial = await links.getInitialLink();
      if (initial != null && revision.value == initialRevision) {
        await capture(initial.toString());
      }
    } catch (_) {
      /* Platform delivery unavailable; the saved invite remains available. */
    }
  }

  static Future<void> capture(String value) async {
    final code = FriendInviteLink.parse(value);
    if (code == null) return;
    await _serialize(() async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_key, code)) return;
      pending.value = code;
      revision.value++;
    });
  }

  static Future<void> consume(String code) async {
    final normalized = FriendInviteLink.normalizeCode(code);
    await _serialize(() async {
      if (normalized == null || pending.value != normalized) return;
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.remove(_key)) return;
      pending.value = null;
      revision.value++;
    });
  }

  @visibleForTesting
  static Future<void> reset() async {
    await _subscription?.cancel();
    await _writes;
    _subscription = null;
    _started = null;
    pending.value = null;
    revision.value = 0;
  }
}
