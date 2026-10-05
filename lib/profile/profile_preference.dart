import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePreference {
  ProfilePreference._();
  static const _displayNameKey = 'profile_display_name';
  static const defaultDisplayName = 'SETKEEPユーザー';
  static final changes = ValueNotifier<int>(0);

  static Future<String> load({String? owner}) async {
    final preferences = await SharedPreferences.getInstance();
    if (owner != null) {
      final cached = preferences.getString('${_displayNameKey}_$owner');
      if (cached != null) return cached.trim();
      if (preferences.getString('${_displayNameKey}_owner') != owner) return '';
    }
    return (preferences.getString(_displayNameKey) ?? '').trim();
  }

  static String socialName(String value) => value.trim().isEmpty
      ? defaultDisplayName
      : String.fromCharCodes(value.trim().runes.take(40));

  static Future<void> setDisplayName(String value, {String? owner}) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_displayNameKey, value.trim())) {
      throw StateError('Display name could not be saved');
    }
    if (owner != null) {
      if (!await preferences.setString(
            '${_displayNameKey}_$owner',
            value.trim(),
          ) ||
          !await preferences.setString('${_displayNameKey}_owner', owner)) {
        throw StateError('Display name could not be saved');
      }
    }
    changes.value++;
  }

  /// Cloud cache is account-scoped and does not rename another account's cache.
  static Future<void> cacheServerName(String owner, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '${_displayNameKey}_$owner';
    if (preferences.getString(key) == value.trim()) return;
    if (!await preferences.setString(key, value.trim())) {
      throw StateError('Display name could not be saved');
    }
  }
}
