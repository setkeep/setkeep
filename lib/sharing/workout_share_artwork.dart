import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'share_photo_frame.dart';

/// Export and preview use the same layout; photo gestures move only the crop.
class WorkoutShareArtwork extends StatelessWidget {
  const WorkoutShareArtwork({
    super.key,
    required this.backgroundBytes,
    required this.date,
    required this.exerciseRows,
  });
  final Uint8List? backgroundBytes;
  final String date;
  final List<Widget> exerciseRows;
  static const centeredLogoOpacity = 0.24;
  static const logoAsset = 'assets/brand/setkeep_share_lockup.png';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final photo = backgroundBytes != null;
      final dateStyle = DefaultTextStyle.of(context).style
          .merge(const TextStyle(color: Colors.white70, fontSize: 12));
      final painter = TextPainter(
        text: TextSpan(text: date, style: dateStyle),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final dateWidth = painter.width;
      painter.dispose();
      return SharePhotoFrame(
        bytes: backgroundBytes,
        foreground: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x22000000),
                  Color(0x55000000),
                  Color(0xE8000000),
                ],
              ),
            ),
          ),
          if (!photo)
            Center(
              child: Opacity(
                opacity: centeredLogoOpacity,
                child: Image.asset(
                  logoAsset,
                  key: const Key('shareBrandLogo'),
                  filterQuality: FilterQuality.high,
                  width: size.maxWidth * 0.82,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              size.maxHeight * (photo ? 0.23 : 0.25),
              22,
              size.maxHeight * 0.10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo) ...[
                  // Crop the existing lockup's transparent side gutters. Its visible
                  // wordmark width matches the measured date, with the same left edge.
                  ClipRect(
                    child: Align(
                      alignment: Alignment.center,
                      widthFactor: 0.9,
                      child: Image.asset(
                        logoAsset,
                        key: const Key('shareBrandLogo'),
                        filterQuality: FilterQuality.high,
                        width: dateWidth / 0.9,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(date, key: const Key('shareDate'), style: dateStyle),
                const SizedBox(height: 20),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 290,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: exerciseRows,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
