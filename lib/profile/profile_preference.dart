import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePreference {
  ProfilePreference._();
  static const _displayNameKey = 'profile_display_name';
  static const defaultDisplayName = 'SETKEEPユーザー';
  static final changes = ValueNotifier<int>(0);

  static Future<String> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getString(_displayNameKey) ?? '').trim();
  }

  static String socialName(String value) => value.trim().isEmpty
      ? defaultDisplayName
      : String.fromCharCodes(value.trim().runes.take(40));

  static Future<void> setDisplayName(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_displayNameKey, value.trim())) {
      throw StateError('Display name could not be saved');
    }
    changes.value++;
  }
}
