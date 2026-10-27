import 'package:flutter/material.dart';

import 'ads_consent.dart';

class AdsPrivacyTile extends StatelessWidget {
  const AdsPrivacyTile({super.key, this.consent});
  final AdsConsent? consent;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: consent ?? AdsConsent.instance,
    builder: (context, _) {
      final consent = this.consent ?? AdsConsent.instance;
      if (!consent.privacyRequired) return const SizedBox.shrink();
      final english = Localizations.localeOf(context).languageCode == 'en';
      return ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: Text(english ? 'Ad privacy settings' : '広告のプライバシー設定'),
        onTap: consent.optionsOpen
            ? null
            : () async {
                try {
                  await consent.showOptions();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          english
                              ? 'Could not open settings. Please try again.'
                              : '設定を開けませんでした。もう一度お試しください。',
                        ),
                      ),
                    );
                  }
                }
              },
      );
    },
  );
}
