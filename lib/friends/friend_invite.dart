import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendInviteLink {
  static const baseUrl = String.fromEnvironment('FRIEND_INVITE_BASE_URL');
  static final _code = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static Uri? get publicBase {
    final uri = Uri.tryParse(baseUrl);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment
        ? uri
        : null;
  }

  static String? parse(String input) {
    final text = input.trim();
    if (_code.hasMatch(text)) return text.toLowerCase();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    String? code;
    if (uri.scheme == 'setkeep' &&
        uri.host == 'friend-invite' &&
        uri.pathSegments.length == 1) {
      code = uri.pathSegments.single;
    } else {
      final base = publicBase;
      if (base == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.origin != base.origin) {
        return null;
      }
      final prefix = '${base.path.replaceFirst(RegExp(r'/$'), '')}/';
      if (!uri.path.startsWith(prefix)) return null;
      code = uri.path.substring(prefix.length);
    }
    return _code.hasMatch(code) ? code.toLowerCase() : null;
  }

  static String url(String code) {
    if (!_code.hasMatch(code)) throw ArgumentError('Invalid invite');
    final base = publicBase;
    return base == null
        ? 'setkeep://friend-invite/$code'
        : '${base.toString().replaceFirst(RegExp(r'/$'), '')}/$code';
  }
}

/// Capture before login; presentation and request require the account gate.
class FriendInviteStore {
  static final pending = ValueNotifier<String?>(null);
  static const _key = 'pending_friend_invite';
  static Future<void>? _started;
  static StreamSubscription<Uri>? _subscription;
  static Future<void> start() => _started ??= _start();
  static Future<void> _start() async {
    final preferences = await SharedPreferences.getInstance();
    pending.value = FriendInviteLink.parse(preferences.getString(_key) ?? '');
    try {
      final links = AppLinks();
      _subscription = links.uriLinkStream.listen(
        (uri) => capture(uri.toString()),
        onError: (Object _) {},
      );
      final initial = await links.getInitialLink();
      if (initial != null) await capture(initial.toString());
    } catch (_) {
      /* Platform link delivery unavailable, manual code remains. */
    }
  }

  static Future<void> capture(String value) async {
    final code = FriendInviteLink.parse(value);
    if (code == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, code)) return;
    pending.value = code;
  }

  static Future<void> consume(String code) async {
    if (pending.value != code) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
    pending.value = null;
  }

  @visibleForTesting
  static Future<void> reset() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = null;
    pending.value = null;
  }
}
