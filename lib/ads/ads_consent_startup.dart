import 'package:flutter/material.dart';

import 'ads_consent.dart';

/// Mount only after onboarding, 16+ confirmation and current legal acceptance.
/// Keep authentication/navigation from overlapping an interactive UMP form.
class AdsConsentStartup extends StatefulWidget {
  const AdsConsentStartup({super.key, required this.child, this.consent});

  final Widget child;
  final AdsConsent? consent;

  @override
  State<AdsConsentStartup> createState() => _AdsConsentStartupState();
}

class _AdsConsentStartupState extends State<AdsConsentStartup> {
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await (widget.consent ?? AdsConsent.instance).prepare();
      } finally {
        // Consent errors block ads, not access to workout records or settings.
        if (mounted) setState(() => _finished = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _finished
      ? widget.child
      : const Scaffold(body: Center(child: CircularProgressIndicator()));
}
