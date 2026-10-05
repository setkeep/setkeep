import 'package:flutter/material.dart';

final _openTrainerNotices = Expando<bool>();

/// Information only: opening this dialog never links or publishes records.
Future<void> showTrainerComingSoon(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_openTrainerNotices[navigator] == true) return;
  _openTrainerNotices[navigator] = true;
  final ja = Localizations.localeOf(context).languageCode == 'ja';
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('trainerComingSoonDialog'),
        title: Text(ja ? '今後公開予定' : 'Planned for a future release'),
        content: SingleChildScrollView(
          child: Text(
            ja
                ? 'トレーナーからのメニュー共有、トレーニング記録の確認、コメントの受け取りに対応する連携機能を今後公開予定です。\n\n現在は準備中のため、連携操作は利用できません。'
                : 'Trainer integration is planned for a future release, with shared workout plans, workout record review and trainer comments.\n\nLinking is unavailable while this feature is being prepared.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ja ? '閉じる' : 'Close'),
          ),
        ],
      ),
    );
  } finally {
    _openTrainerNotices[navigator] = null;
  }
}
