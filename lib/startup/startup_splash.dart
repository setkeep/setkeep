import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef StartupProgress = void Function(double value);

/// The native launch screen is static. This screen continues from its empty
/// track and advances only when an actual startup step has completed.
class StartupSplash<T> extends StatefulWidget {
  const StartupSplash({
    super.key,
    required this.initialize,
    required this.destination,
    required this.background,
    required this.track,
    required this.accent,
    required this.androidLogo,
    required this.iosLogo,
    this.iosLogoSize = 240,
  });

  final Future<T> Function(StartupProgress progress, bool offline) initialize;
  final Widget Function(T result) destination;
  final Color background;
  final Color track;
  final Color accent;
  final String androidLogo;
  final String iosLogo;
  final double iosLogoSize;

  @override
  State<StartupSplash<T>> createState() => _StartupSplashState<T>();
}

class _StartupSplashState<T> extends State<StartupSplash<T>> {
  double _progress = 0;
  T? _result;
  bool _finished = false;
  bool _failed = false;
  int _attempt = 0;
  Stopwatch? _startupClock;
  Timer? _completionHold;
  Duration _animationDuration = const Duration(milliseconds: 220);

  static const _minimumProgressDuration = Duration(milliseconds: 700);
  static const _fullProgressHold = Duration(milliseconds: 180);

  @override
  void dispose() {
    _completionHold?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start(false));
  }

  Future<void> _start(bool offline) async {
    if (!mounted) return;
    final attempt = ++_attempt;
    _completionHold?.cancel();
    _startupClock = Stopwatch()..start();
    setState(() {
      _progress = 0;
      _animationDuration = const Duration(milliseconds: 220);
      _result = null;
      _failed = false;
      _finished = false;
    });
    try {
      final result = await widget.initialize((value) {
        if (!mounted || attempt != _attempt) return;
        // A failed or unfinished startup never displays completion.
        if (!value.isFinite) return;
        setState(() => _progress = value.clamp(_progress, 0.99));
      }, offline);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _result = result;
        final remaining = _minimumProgressDuration - _startupClock!.elapsed;
        _animationDuration = remaining > const Duration(milliseconds: 220)
            ? remaining
            : const Duration(milliseconds: 220);
        _progress = 1;
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.destination(_result as T);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final japanese = Localizations.localeOf(context).languageCode == 'ja';
    return Material(
      color: widget.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Image.asset(
              ios ? widget.iosLogo : widget.androidLogo,
              width: ios ? widget.iosLogoSize : 180,
              height: ios ? widget.iosLogoSize : 180,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            bottom: ios ? 104 : 98,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 172,
                height: 4,
                child: Stack(
                  children: [
                    ColoredBox(
                      color: widget.track,
                      child: const SizedBox.expand(),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _progress),
                      duration: _animationDuration,
                      curve: Curves.easeOut,
                      onEnd: () {
                        if (_progress == 1 && _result != null && mounted) {
                          final attempt = _attempt;
                          _completionHold?.cancel();
                          _completionHold = Timer(_fullProgressHold, () {
                            if (mounted && attempt == _attempt) {
                              setState(() => _finished = true);
                            }
                          });
                        }
                      },
                      builder: (context, value, _) => SizedBox(
                        key: const Key('startupProgressFill'),
                        width: 172 * value,
                        height: 4,
                        child: ColoredBox(color: widget.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_failed)
            Positioned(
              left: 24,
              right: 24,
              bottom: 140,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    japanese
                        ? '起動時の接続を確認できませんでした'
                        : 'Could not connect during startup.',
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _start(false),
                    child: Text(japanese ? '再試行' : 'Retry'),
                  ),
                  TextButton(
                    onPressed: () => _start(true),
                    child: Text(japanese ? 'オフラインで続ける' : 'Continue offline'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
