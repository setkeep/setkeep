import 'profile/profile_edit_dialog.dart';
import 'trainer/trainer_coming_soon.dart';
import 'config/trainer_release.dart';
import 'design/workout_month_calendar.dart';
import 'profile/profile_preference.dart';
export 'profile/profile_preference.dart';
import 'friends/friend_avatar.dart';
import 'friends/friend_invite.dart';
import 'friends/friend_snapshot_journal.dart';
import 'activity_speed.dart';
export 'activity_speed.dart';
import 'design/setkeep_navigation.dart';
import 'sharing/share_photo_frame.dart';
import 'friends/friends_ui.dart';
import 'ads/ads_config.dart';
import 'ads/setkeep_banner_ad.dart';
import 'ads/workout_interstitial.dart';
import 'trainer/trainer_inbox_repository.dart';
import 'friends/friend_comment_inbox.dart';
import 'friends/notification_sources_page.dart';
import 'design/family_theme.dart';
import 'gym/place_equipment_pages.dart';
import 'gym/custom_gym_preference.dart';
export 'gym/custom_gym_preference.dart';
import 'gym/training_place_preference.dart';
import 'gym/gym_equipment_cache.dart';
import 'gym/gym_repository.dart';
import 'gym/training_equipment_confirmation.dart';
import 'gym/gym_pages.dart';
import 'trainer/trainer_sharing_page.dart';
import 'trainer/trainer_repository.dart';
import 'exercise_form_catalog.dart';
import 'exercise_media.dart';
import 'exercise_media_form_view.dart';
import 'exercise_list_thumbnail.dart';
import 'body_tab_colors.dart';
import 'design/app_colors.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:interactive_3d/interactive_3d.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'body_part_illustration.dart';
import 'body_weight.dart';
import 'muscle_targets.dart';
import 'services/supabase_sync_service.dart';
import 'services/account_auth_service.dart';
import 'services/workout_draft_store.dart';
import 'services/android_workout_draft.dart';
import 'startup/startup_splash.dart';
import 'legal/legal_text.dart';

const activeWorkoutDraftStorageKey = AndroidWorkoutDraft.key;
const appDisplayName = 'SETKEEP';
const appVersion = '1.0.0';

enum ExerciseRecordType {
  weightReps,
  assistedReps,
  bodyweightReps,
  timed,
  cardio,
  distance,
  loadedDistance;

  static ExerciseRecordType fromName(String? value) => values.firstWhere(
    (type) => type.name == value,
    orElse: () => ExerciseRecordType.weightReps,
  );

  String get label => switch (this) {
    ExerciseRecordType.weightReps => '重量・回数',
    ExerciseRecordType.assistedReps => '補助重量・回数',
    ExerciseRecordType.bodyweightReps => '自重・回数',
    ExerciseRecordType.timed => '時間',
    ExerciseRecordType.cardio => '有酸素',
    ExerciseRecordType.distance => '時間・距離',
    ExerciseRecordType.loadedDistance => '重量・距離',
  };
}

extension ExerciseRecordTypeUi on ExerciseRecordType {
  bool get hasWeightInput =>
      this == ExerciseRecordType.weightReps ||
      this == ExerciseRecordType.assistedReps;
  bool get usesSets =>
      this != ExerciseRecordType.cardio &&
      this != ExerciseRecordType.distance &&
      this != ExerciseRecordType.loadedDistance;
}

ExerciseRecordType inferRecordType({
  required String name,
  required String bodyPart,
  required String equipment,
}) {
  if (bodyPart == '有酸素') return ExerciseRecordType.cardio;
  if (const {'プランク', 'サイドプランク', 'ウォールシット'}.contains(name)) {
    return ExerciseRecordType.timed;
  }
  if (const {'ランニング', 'ウォーキング', 'サイクリング'}.contains(name)) {
    return ExerciseRecordType.distance;
  }
  if (equipment == '自重') return ExerciseRecordType.bodyweightReps;
  return ExerciseRecordType.weightReps;
}

ExerciseRecordType recordTypeForExerciseName(
  String name, {
  String bodyPart = '',
  String equipment = '',
}) {
  for (final item in [
    ...CustomExercisePreference.exercises,
    ..._legacyExerciseTemplates,
  ]) {
    if (item.name == name) return item.recordType;
  }
  final form = ExerciseFormCatalog.forName(name);
  if (form != null) return ExerciseRecordType.fromName(form.recordType);
  return inferRecordType(name: name, bodyPart: bodyPart, equipment: equipment);
}

String formatVolumeKg(double volume) {
  final raw = volume == volume.roundToDouble()
      ? volume.toStringAsFixed(0)
      : volume.toStringAsFixed(1);
  return raw.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
}

Future<bool> discardDraftBeforeNewWorkout(BuildContext context) async {
  final draft = WorkoutDraftSummary.tryParse(await AndroidWorkoutDraft.read());
  if (draft == null) return true;
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('新しく始めますか？'),
      content: const Text('入力途中の内容は破棄されます。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('破棄して始める'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await AndroidWorkoutDraft.clear();
  return true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SetkeepApp(showStartup: true));
}

class RestNotificationService {
  RestNotificationService._();

  static const _channel = MethodChannel('com.setkeep.app/rest_timer');

  static Future<void> schedule(
    int seconds, {
    DateTime? endsAt,
    String exerciseName = '',
    Map<String, String>? target,
    int? restSeconds,
  }) async {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    try {
      await _channel.invokeMethod<void>('schedule', {
        'seconds': seconds,
        'target': ?target,
        'restSeconds': ?restSeconds,
        'exerciseName': exerciseName,
        'endsAtMilliseconds':
            (endsAt ?? DateTime.now().add(Duration(seconds: seconds)))
                .millisecondsSinceEpoch,
      });
    } on PlatformException catch (error) {
      debugPrint('Rest notification scheduling failed: $error');
    }
  }

  /// Android alone owns natural completion output. This requests the same
  /// native claim as AlarmManager; it is neither cancel nor explicit test sound.
  static Future<void> completeIfDue(DateTime deadline) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('completeIfDue', {
        'endsAtMilliseconds': deadline.millisecondsSinceEpoch,
      });
    } on PlatformException catch (error) {
      debugPrint('Rest completion claim failed: $error');
    }
  }

  static Future<void> cancel({int remainingSeconds = 0}) async {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'remainingSeconds': remainingSeconds,
      });
    } on PlatformException catch (error) {
      debugPrint('Rest notification cancellation failed: $error');
    }
  }

  static Future<bool> pause() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('pause') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Rest timer pause failed: $error');
      return false;
    }
  }

  static Future<bool> resume() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('resume') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Rest timer resume failed: $error');
      return false;
    }
  }

  static Future<bool> extend() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('extend') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Rest timer extension failed: $error');
      return false;
    }
  }

  static void listen(VoidCallback? listener) {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    _channel.setMethodCallHandler(
      listener == null
          ? null
          : (call) async {
              if (call.method == 'stateChanged') listener();
            },
    );
  }

  static Future<Map<String, dynamic>?> state() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return null;
    try {
      return await _channel.invokeMapMethod<String, dynamic>('state');
    } on PlatformException catch (error) {
      debugPrint('Rest timer state unavailable: $error');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> playCompletionFeedback() async {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      await SystemSound.play(SystemSoundType.alert);
      return;
    }
    try {
      await _channel.invokeMethod<void>('playCompletionFeedback');
    } on PlatformException catch (error) {
      debugPrint('Rest completion sound failed: $error');
      await SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
    }
  }
}

class WorkoutImageService {
  WorkoutImageService._();

  static const _channel = MethodChannel('com.setkeep.app/workout_image');
  @visibleForTesting
  static Future<void> Function(Uint8List)? saveOverride;
  @visibleForTesting
  static Future<Uint8List> Function()? captureOverride;

  static Future<void> save(Uint8List bytes) async {
    if (saveOverride case final override?) {
      await override(bytes);
      return;
    }
    if (!(Platform.isIOS || Platform.isAndroid)) {
      throw UnsupportedError('Image saving is only supported on mobile');
    }
    await _channel.invokeMethod<void>('save', {
      'bytes': bytes,
      'fileName': 'SETKEEP_${DateTime.now().millisecondsSinceEpoch}.png',
    });
  }
}

class DeviceInfoService {
  DeviceInfoService._();

  static const _channel = MethodChannel('com.setkeep.app/workout_image');

  static Future<String> summary() async {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    }
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'deviceInfo',
      );
      if (info == null) throw const FormatException('Device info unavailable');
      return '${info['os'] ?? Platform.operatingSystem} / ${info['device'] ?? '端末情報不明'}';
    } catch (_) {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    }
  }
}

// Round upward so a fractional final second is never treated as finished.
int remainingRestSeconds(DateTime deadline, DateTime now) =>
    math.max(0, (deadline.difference(now).inMicroseconds / 1000000).ceil());

class RestTimerPreference {
  RestTimerPreference._();

  static const _enabledKey = 'rest_timer_enabled';
  static const _secondsKey = 'rest_timer_seconds';
  static bool enabled = false;
  static int seconds = 90;

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    enabled = preferences.getBool(_enabledKey) ?? false;
    seconds = preferences.getInt(_secondsKey) ?? 90;
  }

  static Future<void> setEnabled(bool value) async {
    enabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
    if (!value) await RestNotificationService.cancel();
  }

  static Future<void> setSeconds(int value) async {
    seconds = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_secondsKey, value);
  }
}

class WorkoutUiPreference {
  WorkoutUiPreference._();

  static const _completionCheckKey = 'completion_check_enabled';
  static const _workoutTimerKey = 'workout_timer_enabled';
  static const _workoutDurationKey = 'workout_duration_enabled';
  static bool completionCheckEnabled = true;
  static bool workoutTimerEnabled = true;
  static bool workoutDurationEnabled = true;

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    completionCheckEnabled = preferences.getBool(_completionCheckKey) ?? true;
    workoutTimerEnabled = preferences.getBool(_workoutTimerKey) ?? true;
    workoutDurationEnabled = preferences.getBool(_workoutDurationKey) ?? true;
    // Older versions exposed these as two independent settings. Preserve an
    // enabled capability and migrate both keys to the single setting.
    final trainingDurationEnabled =
        workoutTimerEnabled && workoutDurationEnabled;
    workoutTimerEnabled = trainingDurationEnabled;
    workoutDurationEnabled = trainingDurationEnabled;
    await preferences.setBool(_workoutTimerKey, trainingDurationEnabled);
    await preferences.setBool(_workoutDurationKey, trainingDurationEnabled);
    if (!completionCheckEnabled && RestTimerPreference.enabled) {
      await RestTimerPreference.setEnabled(false);
    }
  }

  static Future<void> setCompletionCheckEnabled(bool value) async {
    completionCheckEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completionCheckKey, value);
    if (!value) {
      await RestTimerPreference.setEnabled(false);
      await RestNotificationService.cancel();
    }
  }

  static Future<void> setWorkoutTimerEnabled(bool value) async {
    workoutTimerEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_workoutTimerKey, value);
  }

  static Future<void> setWorkoutDurationEnabled(bool value) async {
    workoutDurationEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_workoutDurationKey, value);
  }

  static Future<void> setTrainingDurationEnabled(bool value) async {
    await setWorkoutTimerEnabled(value);
    await setWorkoutDurationEnabled(value);
  }
}

class SetkeepApp extends StatelessWidget {
  const SetkeepApp({super.key, this.showStartup = false, this.auth});

  final bool showStartup;
  final AccountAuthService? auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      builder: (context, child) {
        unawaited(FriendInviteStore.start());
        return AdsScope(
          config: const AdsConfig(generalApp: true),
          entitlement: setkeepAdsEntitlement,
          child: child!,
        );
      },
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ja', 'JP')],
      theme: familyTheme(),
      navigatorObservers: [exerciseMediaRouteObserver],
      home: showStartup
          ? _SetkeepStartup(auth: auth)
          : _OnboardingGate(auth: auth),
    );
  }
}

class _SetkeepStartup extends StatelessWidget {
  const _SetkeepStartup({this.auth});

  final AccountAuthService? auth;

  @override
  Widget build(
    BuildContext context,
  ) => StartupSplash<({bool onboarded, bool consented})>(
    background: const Color(0xFFF4F5F0),
    track: const Color(0xFFDDE0DE),
    accent: AppColors.primaryGreen,
    androidLogo: 'android/app/src/main/res/drawable-xxxhdpi/launch_logo.png',
    iosLogo:
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
    initialize: (progress, offline) async {
      await RestTimerPreference.load();
      progress(0.17);
      await WorkoutUiPreference.load();
      progress(0.34);
      await CustomExercisePreference.load();
      progress(0.51);
      await SupabaseConfig.initialize();
      if (!offline && SupabaseConfig.initializationError != null) {
        throw SupabaseConfig.initializationError!;
      }
      progress(0.70);
      final onboarded = await OnboardingPreference.load();
      progress(0.84);
      final consented = await LegalConsentPreference.load();
      return (onboarded: onboarded, consented: consented);
    },
    destination: (result) => _SetkeepInitialScreen(
      onboarded: result.onboarded,
      consented: result.consented,
      auth: auth,
    ),
  );
}

class _SetkeepInitialScreen extends StatefulWidget {
  const _SetkeepInitialScreen({
    required this.onboarded,
    required this.consented,
    this.auth,
  });

  final bool onboarded;
  final bool consented;
  final AccountAuthService? auth;

  @override
  State<_SetkeepInitialScreen> createState() => _SetkeepInitialScreenState();
}

class _SetkeepInitialScreenState extends State<_SetkeepInitialScreen> {
  late bool _onboarded = widget.onboarded;
  late bool _consented = widget.consented;

  @override
  Widget build(BuildContext context) {
    if (!_onboarded) {
      return _OnboardingPage(
        onFinished: () => setState(() => _onboarded = true),
      );
    }
    if (!_consented) {
      return _LegalConsentPage(
        onFinished: () => setState(() => _consented = true),
      );
    }
    return _RequiredAccountGate(auth: widget.auth);
  }
}

class OnboardingPreference {
  OnboardingPreference._();

  static const _completedKey = 'onboarding_completed';

  static Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  static Future<void> complete() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_completedKey, true)) {
      throw StateError('Onboarding could not be saved');
    }
  }
}

class LegalDocuments {
  static const termsVersion = 'terms-1.0';
  static const privacyVersion = 'privacy-1.0';
  // These can later be served at public URLs without changing consent storage.
  static const String? termsUrl = null;
  static const String? privacyUrl = null;
  static const terms = setkeepTerms;
  static const privacy = setkeepPrivacy;
}

class LegalConsentPreference {
  LegalConsentPreference._();

  static const _key = 'legal_consent';

  static Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final data = jsonDecode(preferences.getString(_key) ?? 'null');
      return data is Map &&
          data['accepted'] == true &&
          data['over16'] == true &&
          data['termsVersion'] == LegalDocuments.termsVersion &&
          data['privacyVersion'] == LegalDocuments.privacyVersion &&
          data['acceptedAt'] is String &&
          DateTime.tryParse(data['acceptedAt'] as String) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> accept({
    required bool over16,
    required bool terms,
    required bool privacy,
  }) async {
    if (!over16 || !terms || !privacy) {
      throw StateError('All confirmations are required');
    }
    final preferences = await SharedPreferences.getInstance();
    // One write keeps the acceptance, timestamp and versions together.
    final saved = await preferences.setString(
      _key,
      jsonEncode({
        'accepted': true,
        'over16': true,
        'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        'termsVersion': LegalDocuments.termsVersion,
        'privacyVersion': LegalDocuments.privacyVersion,
      }),
    );
    if (!saved) throw StateError('Consent could not be saved');
  }
}

class _LegalConsentGate extends StatefulWidget {
  const _LegalConsentGate({this.auth});

  final AccountAuthService? auth;

  @override
  State<_LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<_LegalConsentGate> {
  late final Future<bool> _accepted = LegalConsentPreference.load();
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    if (_finished) return _RequiredAccountGate(auth: widget.auth);
    return FutureBuilder<bool>(
      future: _accepted,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return _RequiredAccountGate(auth: widget.auth);
        }
        return _LegalConsentPage(
          onFinished: () => setState(() => _finished = true),
        );
      },
    );
  }
}

class _LegalConsentPage extends StatefulWidget {
  const _LegalConsentPage({required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<_LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<_LegalConsentPage> {
  bool _over16 = false;
  bool _terms = false;
  bool _privacy = false;
  bool _saving = false;

  void _openDocument(String title, String content) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(
              content,
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await LegalConsentPreference.accept(
        over16: _over16,
        terms: _terms,
        privacy: _privacy,
      );
      if (mounted) widget.onFinished();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('legalConsent'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.fact_check_outlined,
              size: 56,
              color: AppColors.primaryGreenDeep,
            ),
            const SizedBox(height: 20),
            const Text(
              'ご利用の前に',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const Text('内容をご確認のうえ、3項目すべてにチェックしてください。'),
            const SizedBox(height: 12),
            const Text('利用規約とプライバシーポリシーをご確認ください。'),
            TextButton(
              key: const Key('openTerms'),
              onPressed: () => _openDocument('利用規約', LegalDocuments.terms),
              child: const Text('利用規約を読む'),
            ),
            TextButton(
              key: const Key('openPrivacy'),
              onPressed: () =>
                  _openDocument('プライバシーポリシー', LegalDocuments.privacy),
              child: const Text('プライバシーポリシーを読む'),
            ),
            CheckboxListTile(
              key: const Key('confirmOver16'),
              contentPadding: EdgeInsets.zero,
              title: const Text('私は16歳以上です'),
              value: _over16,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _over16 = value!),
            ),
            CheckboxListTile(
              key: const Key('confirmTerms'),
              contentPadding: EdgeInsets.zero,
              title: const Text('利用規約に同意します'),
              value: _terms,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _terms = value!),
            ),
            CheckboxListTile(
              key: const Key('confirmPrivacy'),
              contentPadding: EdgeInsets.zero,
              title: const Text('プライバシーポリシーに同意します'),
              value: _privacy,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _privacy = value!),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('acceptLegalConsent'),
              onPressed: _over16 && _terms && _privacy && !_saving
                  ? _save
                  : null,
              child: const Text('同意して次へ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate({this.auth});

  final AccountAuthService? auth;

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late final Future<bool> _completed = OnboardingPreference.load();
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    if (_finished) return _LegalConsentGate(auth: widget.auth);
    return FutureBuilder<bool>(
      future: _completed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) return _LegalConsentGate(auth: widget.auth);
        return _OnboardingPage(
          onFinished: () => setState(() => _finished = true),
        );
      },
    );
  }
}

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

/// The only route from onboarding and consent into the general app.
/// Supabase restores its persisted session during startup; no guest route is
/// available when configuration or authentication is missing.
class _RequiredAccountGate extends StatefulWidget {
  const _RequiredAccountGate({this.auth});

  final AccountAuthService? auth;

  @override
  State<_RequiredAccountGate> createState() => _RequiredAccountGateState();
}

class _RequiredAccountGateState extends State<_RequiredAccountGate> {
  AccountAuthService? _auth;
  StreamSubscription<void>? _subscription;
  bool _signedIn = false;
  bool _authError = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.auth ?? SupabaseAccountAuthService.configured());
  }

  void _attach(AccountAuthService? auth) {
    _subscription?.cancel();
    _auth = auth;
    _signedIn = auth?.isSignedIn ?? false;
    _subscription = auth?.changes.listen(
      (_) {
        if (!mounted) return;
        final wasSignedIn = _signedIn;
        setState(() {
          _signedIn = auth.isSignedIn;
          _authError = false;
        });
        if (wasSignedIn && !_signedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // A transient refresh error must not hide local history when a
        // restored session is still available on this device.
        if (mounted && !_signedIn) setState(() => _authError = true);
      },
    );
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await SupabaseConfig.initialize();
    if (!mounted) return;
    setState(() {
      _authError = SupabaseConfig.initializationError != null;
      _attach(widget.auth ?? SupabaseAccountAuthService.configured());
      _retrying = false;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retrying) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_auth == null || _authError) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('現在アカウント機能を利用できません'),
                Text(
                  _authError || SupabaseConfig.initializationError != null
                      ? 'ログイン状態を確認できませんでした。通信状態を確認してください。'
                      : '接続設定を確認してください。',
                ),
                TextButton(onPressed: _retry, child: const Text('再試行')),
              ],
            ),
          ),
        ),
      );
    }
    if (_signedIn) return const HomeShell();
    return CloudAccountPage(
      key: const Key('requiredAccountPage'),
      historyCount: 0,
      onSyncRequested: () async => 0,
      auth: _auth,
      showBackupSection: false,
    );
  }
}

class _OnboardingPageState extends State<_OnboardingPage> {
  static const _slides = [
    (
      icon: Icons.fitness_center_rounded,
      title: 'ジムと一緒にトレーニングを記録',
      body:
          '種目・重量・回数・セットをかんたんに記録。'
          '\nジムを選んで、その日の場所も記録。未登録の場所も追加できます。'
          '\n店舗の設備情報と連動し、そのジムでできる種目も探せます。',
    ),
    (
      icon: Icons.insights_rounded,
      title: '成長を可視化',
      body:
          '履歴と筋肉ヒートマップで、積み重ねを振り返りましょう。'
          '\n対応種目のフォームガイド動画で動きも確認できます。',
    ),
    (
      icon: Icons.qr_code_rounded,
      title: 'SETKEEP TRAINERと連携',
      body:
          'SETKEEP TRAINERが表示する招待QRコードを読み取れます。'
          '\nメニューやコメントを受け取ったり、トレーニング記録を共有できます。',
    ),
    (
      icon: Icons.cloud_outlined,
      title: 'アカウントでSETKEEPをもっと便利に',
      body:
          'アカウントを使ってSETKEEP TRAINERとの連携などの機能を利用できます。'
          '\nクラウドバックアップは現在準備中です。',
    ),
  ];
  final _controller = PageController();
  int _page = 0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await OnboardingPreference.complete();
      if (mounted) widget.onFinished();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('onboarding'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                physics: _saving ? const NeverScrollableScrollPhysics() : null,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text('SETKEEP'),
                        const SizedBox(height: 28),
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: AppColors.primaryGreen,
                          child: Icon(slide.icon, size: 48),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, height: 1.7),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  Text(
                    '${_page + 1} / ${_slides.length}',
                    key: const Key('onboardingIndicator'),
                    semanticsLabel: '全4ページ中${_page + 1}ページ目',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const Key('onboardingBack'),
                          onPressed: _page == 0 || _saving
                              ? null
                              : () => _move(_page - 1),
                          child: const Text('戻る'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('onboardingNext'),
                          onPressed: _saving
                              ? null
                              : _page == 3
                              ? _finish
                              : () => _move(_page + 1),
                          child: Text(_page == 3 ? 'はじめる' : '次へ'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _storageKey = FriendSnapshotJournal.historyKey;
  static const _gymStorageKey = 'selected_gym';
  int _selectedIndex = 0;
  int _friendsRefresh = 0;
  bool _openingFriendInvite = false;
  List<WorkoutRecord> _history = [];
  bool _historyLoaded = false;
  List<BodyWeightEntry> _bodyWeights = [];
  String? _selectedGym;
  List<SavedWorkoutTemplate> _workoutTemplates = [];
  WorkoutDraftSummary? _workoutDraft;
  StreamSubscription<AuthState>? _trainerAuthSubscription;
  late final Future<void> _historyReady;
  bool _trainerSyncRunning = false;
  bool _trainerSyncPending = false;
  Future<void> _historyMutation = Future<void>.value();
  final _friendJournal = FriendSnapshotJournal();
  Timer? _friendDeletionRetry;
  bool _friendForeground = true;
  String? _lastFriendOwner;
  String? get _friendOwner => SupabaseConfig.initialized
      ? Supabase.instance.client.auth.currentUser?.id
      : null;
  String? get _friendOwnerAtIntent => _friendOwner ?? _lastFriendOwner;

  Future<T> _withHistoryMutation<T>(Future<T> Function() action) {
    final result = _historyMutation.then((_) => action());
    _historyMutation = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  void initState() {
    super.initState();
    _lastFriendOwner = _friendOwner;
    WidgetsBinding.instance.addObserver(this);
    _historyReady = _loadHistory();
    FriendInviteStore.pending.addListener(_showFriendInvite);
    unawaited(FriendInviteStore.start().then((_) => _showFriendInvite()));
    unawaited(_historyReady.then((_) => _syncTrainerHistory()));
    unawaited(_retryFriendDeletions());
    _startFriendDeletionRetry();
    unawaited(_syncTrainingEquipment());
    if (SupabaseConfig.initialized) {
      _trainerAuthSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.event == AuthChangeEvent.tokenRefreshed) {
              unawaited(_retryFriendDeletions());
              return;
            }
            if (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.initialSession ||
                state.event == AuthChangeEvent.signedOut) {
              if (mounted) setState(() {});
              _startFriendDeletionRetry();
              if (state.session != null) {
                _lastFriendOwner = state.session!.user.id;
                unawaited(
                  _friendJournal
                      .rememberOwner(state.session!.user.id)
                      .catchError((Object _) {}),
                );
                unawaited(_syncTrainerHistory());
                unawaited(_syncTrainingEquipment());
                unawaited(_retryFriendDeletions());
              }
            }
          });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _friendForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      setState(() => _friendsRefresh++);
      unawaited(_syncTrainerHistory());
      unawaited(_syncTrainingEquipment());
      unawaited(_retryFriendDeletions());
      _startFriendDeletionRetry();
    } else {
      _friendDeletionRetry?.cancel();
    }
  }

  void _startFriendDeletionRetry() {
    _friendDeletionRetry?.cancel();
    if (_friendOwner == null || !_friendForeground) return;
    _friendDeletionRetry = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_retryFriendDeletions());
    });
  }

  Future<void> _retryFriendDeletions() async {
    try {
      await _historyReady;
      if (!mounted || !_friendForeground) return;
      final owner = _friendOwner;
      if (owner == null) return;
      await _friendJournal.rememberOwner(owner);
      await configuredFriends()?.retryDeletions();
    } catch (_) {
      // Durable intents remain until the same account can retry successfully.
    }
  }

  @override
  void dispose() {
    FriendInviteStore.pending.removeListener(_showFriendInvite);
    WidgetsBinding.instance.removeObserver(this);
    _trainerAuthSubscription?.cancel();
    _friendDeletionRetry?.cancel();
    super.dispose();
  }

  void _showFriendInvite() {
    final code = FriendInviteStore.pending.value;
    if (code == null ||
        _openingFriendInvite ||
        !mounted ||
        configuredFriends() == null) {
      return;
    }
    _openingFriendInvite = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _historyReady;
        if (!mounted) return;
        final repo = configuredFriends();
        if (repo == null) return;
        await FriendInviteStore.consume(code);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendsSettingsPage(
              repository: repo,
              history: _visibleHistory,
              initialInvite: code,
            ),
          ),
        );
        if (mounted) setState(() => _friendsRefresh++);
      } finally {
        _openingFriendInvite = false;
        if (mounted && FriendInviteStore.pending.value != null) {
          _showFriendInvite();
        }
      }
    });
  }

  List<WorkoutRecord> get _visibleHistory {
    final userId = SupabaseConfig.initialized
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    return _history
        .where(
          (w) =>
              w.trainerWorkoutId == null ||
              (userId != null && w.trainerOwnerUserId == userId),
        )
        .toList();
  }

  Future<void> _syncTrainingEquipment() async {
    await _historyReady;
    if (!mounted) return;
    try {
      await TrainingEquipmentServices.journal.reconcile(
        _history.map(equipmentWorkoutFromRecord).toList(),
      );
    } catch (error) {
      debugPrint('Equipment confirmation sync deferred: $error');
    }
  }

  Future<void> _syncTrainerHistory() async {
    await _historyReady;
    if (!mounted || !SupabaseConfig.initialized) return;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    if (_trainerSyncRunning) {
      _trainerSyncPending = true;
      return;
    }
    _trainerSyncRunning = true;
    try {
      final repo = TrainerRepository(client);
      await _withHistoryMutation(() async {
        final rows = await fetchAllTrainerWorkouts(
          (offset) => repo.recordedForMe(offset: offset),
        );
        if (!mounted || client.auth.currentUser?.id != userId) return;
        final updated = reconcileTrainerWorkouts(_history, rows, userId);
        await _persistHistory(updated, owner: userId);
        if (mounted && client.auth.currentUser?.id == userId) {
          setState(() => _history = updated);
        }
      });
    } catch (error) {
      debugPrint('Trainer workout sync failed: $error');
    } finally {
      _trainerSyncRunning = false;
      if (_trainerSyncPending) {
        _trainerSyncPending = false;
        unawaited(_syncTrainerHistory());
      }
    }
  }

  Future<void> _loadHistory() async {
    final owner = _friendOwner;
    if (owner != null) await _friendJournal.rememberOwner(owner);
    final rememberedOwner = await _friendJournal.lastOwner();
    _lastFriendOwner ??= rememberedOwner;
    final encoded = await _friendJournal.recoverHistory();
    final preferences = await SharedPreferences.getInstance();
    final workoutTemplates = await WorkoutTemplatePreference.load();
    final bodyWeights = await BodyWeightPreference.load();
    await CustomGymPreference.load();
    final selectedGym = preferences.getString(_gymStorageKey);
    if (selectedGym != null &&
        !standardGyms.contains(selectedGym) &&
        !CustomGymPreference.gyms.contains(selectedGym)) {
      await CustomGymPreference.add(selectedGym);
    }
    await TrainingPlacePreference.migrateKanekinPlace(GymServices.repository);
    final defaultPlace = await TrainingPlacePreference.load();
    final workoutDraft = WorkoutDraftSummary.tryParse(
      await AndroidWorkoutDraft.read(),
    );
    if (!mounted) return;
    final items = sortWorkoutsNewestFirst(decodeWorkoutHistory(encoded));
    setState(() {
      _history = items;
      _historyLoaded = true;
      _bodyWeights = bodyWeights;
      _selectedGym = defaultPlace.name;
      _workoutTemplates = workoutTemplates;
      _workoutDraft = workoutDraft;
    });
  }

  Future<void> _refreshWorkoutDraft() async {
    final draft = WorkoutDraftSummary.tryParse(
      await AndroidWorkoutDraft.read(),
    );
    if (mounted) setState(() => _workoutDraft = draft);
  }

  Future<void> _discardWorkoutDraft() async {
    await AndroidWorkoutDraft.clear();
    if (mounted) setState(() => _workoutDraft = null);
  }

  Future<void> _saveWorkoutTemplate(SavedWorkoutTemplate template) async {
    final updated = [
      template,
      ..._workoutTemplates.where((item) => item.name != template.name),
    ];
    setState(() => _workoutTemplates = updated);
    await WorkoutTemplatePreference.save(updated);
  }

  Future<void> _deleteWorkoutTemplate(SavedWorkoutTemplate template) async {
    final updated = _workoutTemplates
        .where((item) => item.name != template.name)
        .toList();
    setState(() => _workoutTemplates = updated);
    await WorkoutTemplatePreference.save(updated);
  }

  Future<void> _replaceWorkoutTemplates(
    List<SavedWorkoutTemplate> templates,
  ) async {
    final updated = List<SavedWorkoutTemplate>.from(templates);
    setState(() => _workoutTemplates = updated);
    await WorkoutTemplatePreference.save(updated);
  }

  Future<void> _saveWorkout(WorkoutRecord workout) {
    final owner = _friendOwnerAtIntent;
    return _withHistoryMutation(() async {
      if (workout.trainerWorkoutId != null) {
        await _trainerRecordRepository(workout)
            .restoreRecordedWorkout(workout.trainerWorkoutId!);
      }
      final updated = sortWorkoutsNewestFirst([
        workout,
        ..._history.where((w) => !_sameWorkout(w, workout)),
      ]);
      await _persistHistory(updated, owner: owner);
      if (mounted) setState(() => _history = updated);
      unawaited(_syncHistory(updated));
    });
  }

  Future<void> _persistHistory(
    List<WorkoutRecord> history, {
    required String? owner,
  }) async {
    await _friendJournal.saveHistory(
      history.map((item) => item.toJson()).toList(),
      expectedOwner: owner,
    );
    final friends = owner == _friendOwner ? configuredFriends() : null;
    if (friends != null) {
      unawaited(
        friends.publish(history.map((w) => w.toJson()).toList()).catchError((
          Object _,
        ) {
          /* Durable deletions retry on resume, login and while foregrounded. */
        }),
      );
    }
    unawaited(
      TrainingEquipmentServices.journal
          .reconcile(history.map(equipmentWorkoutFromRecord).toList())
          .catchError((Object error) {
            debugPrint('Equipment confirmation sync deferred: $error');
          }),
    );
  }

  Future<void> _saveBodyWeight(BodyWeightEntry entry) async {
    final updated = sortBodyWeights([
      ..._bodyWeights.where((item) => item.id != entry.id),
      entry,
    ]);
    setState(() => _bodyWeights = updated);
    await BodyWeightPreference.save(updated);
  }

  Future<void> _deleteBodyWeight(BodyWeightEntry entry) async {
    final updated = _bodyWeights.where((item) => item.id != entry.id).toList();
    await BodyWeightPreference.save(updated);
    if (mounted) setState(() => _bodyWeights = updated);
  }

  Future<void> _replaceWorkout(WorkoutRecord original, WorkoutRecord workout) {
    final owner = _friendOwnerAtIntent;
    return _withHistoryMutation(() async {
      if (original.trainerWorkoutId != null) {
        await _trainerRecordRepository(original).updateRecordedWorkout(
          original.trainerWorkoutId!,
          workout.sets.map((s) => s.toJson()).toList(),
        );
      }
      final updated = sortWorkoutsNewestFirst([
        if (workout.sets.isNotEmpty) workout,
        ..._history.where((item) => !_sameWorkout(item, original)),
      ]);
      await _persistHistory(updated, owner: owner);
      if (mounted) setState(() => _history = updated);
      unawaited(_syncHistory(updated));
    });
  }

  TrainerRepository _trainerRecordRepository(WorkoutRecord workout) {
    if (!SupabaseConfig.initialized ||
        Supabase.instance.client.auth.currentUser?.id !=
            workout.trainerOwnerUserId) {
      throw StateError('記録の所有者としてログインしてください');
    }
    return TrainerRepository(Supabase.instance.client);
  }

  Future<bool> _deleteWorkout(WorkoutRecord workout) {
    final owner = _friendOwnerAtIntent;
    return _withHistoryMutation(() async {
      try {
        if (workout.trainerWorkoutId != null) {
          await _trainerRecordRepository(workout)
              .deleteRecordedWorkout(workout.trainerWorkoutId!);
        } else if (SupabaseSyncService.canUseCloud) {
          await SupabaseSyncService.deleteWorkout(
            workout.date.toIso8601String(),
          );
        }
        final updated = _history
            .where((item) => !_sameWorkout(item, workout))
            .toList();
        await _persistHistory(updated, owner: owner);
        if (mounted) setState(() => _history = updated);
        return true;
      } catch (error) {
        debugPrint('Workout delete failed: $error');
        return false;
      }
    });
  }

  Future<int> _importWorkouts(
    List<WorkoutRecord> imported,
  ) => _withHistoryMutation(() async {
    final owner = _friendOwner;
    final merged = <String, WorkoutRecord>{
      for (final workout in _history.where((w) => w.trainerWorkoutId == null))
        workout.date.toIso8601String(): workout,
      for (final workout in imported.where((w) => w.trainerWorkoutId == null))
        workout.date.toIso8601String(): workout,
    };
    final trainerRecords = <String, WorkoutRecord>{
      for (final workout in _history.where((w) => w.trainerWorkoutId != null))
        '${workout.trainerOwnerUserId}:${workout.trainerWorkoutId}': workout,
      for (final workout in imported.where((w) => w.trainerWorkoutId != null))
        '${workout.trainerOwnerUserId}:${workout.trainerWorkoutId}': workout,
    };
    final updated = sortWorkoutsNewestFirst([
      ...merged.values,
      ...trainerRecords.values,
    ]);
    final addedCount = updated.length - _history.length;
    await _persistHistory(updated, owner: owner);
    setState(() => _history = updated);
    unawaited(_syncHistory(updated));
    return addedCount;
  });

  Future<int> _importBackup(SetkeepBackup backup) async {
    final addedCount = await _importWorkouts(backup.workouts);
    if (backup.selectedGym != null) await _saveGym(backup.selectedGym!);
    if (backup.restTimerEnabled != null) {
      await _saveRestTimerEnabled(backup.restTimerEnabled!);
    }
    if (backup.restTimerSeconds != null) {
      await _saveRestTimerSeconds(backup.restTimerSeconds!);
    }
    if (backup.completionCheckEnabled != null) {
      await _saveCompletionCheckEnabled(backup.completionCheckEnabled!);
    }
    if (backup.workoutTimerEnabled != null ||
        backup.workoutDurationEnabled != null) {
      if (backup.workoutTimerEnabled != null) {
        await _saveWorkoutTimerEnabled(backup.workoutTimerEnabled!);
      }
      if (backup.workoutDurationEnabled != null) {
        await _saveWorkoutDurationEnabled(backup.workoutDurationEnabled!);
      }
    }

    final templates = <String, SavedWorkoutTemplate>{
      for (final item in _workoutTemplates) item.name: item,
      for (final item in backup.workoutTemplates) item.name: item,
    }.values.toList();
    setState(() => _workoutTemplates = templates);
    await WorkoutTemplatePreference.save(templates);

    final customExercises = <String, ExerciseTemplate>{
      for (final item in CustomExercisePreference.exercises) item.name: item,
      for (final item in backup.customExercises) item.name: item,
    }.values.toList();
    await CustomExercisePreference.replaceAll(customExercises);
    await CustomGymPreference.replaceAll([
      ...CustomGymPreference.gyms,
      ...backup.customGyms,
    ]);
    final bodyWeights = <String, BodyWeightEntry>{
      for (final item in _bodyWeights) item.id: item,
      for (final item in backup.bodyWeights) item.id: item,
    }.values;
    final sortedBodyWeights = sortBodyWeights(bodyWeights);
    setState(() => _bodyWeights = sortedBodyWeights);
    await BodyWeightPreference.save(sortedBodyWeights);
    return addedCount;
  }

  Future<int> _syncHistory([List<WorkoutRecord>? history]) =>
      _withHistoryMutation(() async {
        if (!SupabaseSyncService.canUseCloud) return 0;
        try {
          final localHistory = _history;
          await SupabaseSyncService.syncWorkouts(
            localHistory
                .where((w) => w.trainerWorkoutId == null)
                .map((item) => item.toJson())
                .toList(),
          );
          final cloudItems = await SupabaseSyncService.fetchWorkouts();
          if (!SupabaseSyncService.isSignedIn ||
              !SupabaseSyncService.canUseCloud) {
            return 0;
          }

          final merged = <String, WorkoutRecord>{
            for (final workout in localHistory.where(
              (w) => w.trainerWorkoutId == null,
            ))
              workout.date.toIso8601String(): workout,
          };
          for (final item in cloudItems) {
            final workout = WorkoutRecord.tryFromJson(item);
            if (workout == null) continue;
            merged[workout.date.toIso8601String()] = workout;
          }
          final updated = sortWorkoutsNewestFirst([
            ...merged.values,
            ...localHistory.where((w) => w.trainerWorkoutId != null),
          ]);
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(
            _storageKey,
            jsonEncode(updated.map((item) => item.toJson()).toList()),
          );
          if (mounted) setState(() => _history = updated);
          return updated.length;
        } catch (error) {
          debugPrint('Supabase sync failed: $error');
          return 0;
        }
      });

  Future<void> _saveGym(String gym) async {
    await CustomGymPreference.add(gym);
    await _setGym(gym);
  }

  Future<void> _setGym(String? gym) async {
    setState(() => _selectedGym = gym);
    final preferences = await SharedPreferences.getInstance();
    if (gym == null) {
      await preferences.remove(_gymStorageKey);
    } else {
      await preferences.setString(_gymStorageKey, gym);
    }
  }

  Future<void> _saveRestTimerEnabled(bool enabled) async {
    await RestTimerPreference.setEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveRestTimerSeconds(int seconds) async {
    await RestTimerPreference.setSeconds(seconds);
    if (mounted) setState(() {});
  }

  Future<void> _saveCompletionCheckEnabled(bool enabled) async {
    await WorkoutUiPreference.setCompletionCheckEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveWorkoutTimerEnabled(bool enabled) async {
    await WorkoutUiPreference.setWorkoutTimerEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _saveWorkoutDurationEnabled(bool enabled) async {
    await WorkoutUiPreference.setWorkoutDurationEnabled(enabled);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        history: _visibleHistory,
        friendsHistoryReady: _historyLoaded,
        friendsRefresh: _friendsRefresh,
        bodyWeights: _bodyWeights,
        selectedGym: _selectedGym,
        onGymChanged: _saveGym,
        onWorkoutCompleted: _saveWorkout,
        onWorkoutUpdated: _replaceWorkout,
        onWorkoutDeleted: _deleteWorkout,
        onBodyWeightSaved: _saveBodyWeight,
        onBodyWeightDeleted: _deleteBodyWeight,
        workoutTemplates: _workoutTemplates,
        onTemplateSaved: _saveWorkoutTemplate,
        onTemplateDeleted: _deleteWorkoutTemplate,
        workoutDraft: _workoutDraft,
        onDraftChanged: _refreshWorkoutDraft,
        onDraftDiscarded: _discardWorkoutDraft,
      ),
      MonthlyHistoryPage(
        history: _visibleHistory,
        selectedGym: _selectedGym,
        onWorkoutCompleted: _saveWorkout,
        onWorkoutUpdated: _replaceWorkout,
        onWorkoutDeleted: _deleteWorkout,
      ),
      BodyMapPage(history: _visibleHistory, active: _selectedIndex == 2),
      ProfilePage(
        selectedGym: _selectedGym,
        history: _visibleHistory,
        onSyncRequested: _syncHistory,
        onTrainerLinked: _syncTrainerHistory,
        workoutTemplates: _workoutTemplates,
        bodyWeights: _bodyWeights,
        onBackupImported: _importBackup,
        restTimerEnabled: RestTimerPreference.enabled,
        restTimerSeconds: RestTimerPreference.seconds,
        completionCheckEnabled: WorkoutUiPreference.completionCheckEnabled,
        workoutTimerEnabled: WorkoutUiPreference.workoutTimerEnabled,
        workoutDurationEnabled: WorkoutUiPreference.workoutDurationEnabled,
        onRestTimerEnabledChanged: _saveRestTimerEnabled,
        onRestTimerSecondsChanged: _saveRestTimerSeconds,
        onCompletionCheckEnabledChanged: _saveCompletionCheckEnabled,
        onWorkoutTimerEnabledChanged: _saveWorkoutTimerEnabled,
        onWorkoutDurationEnabledChanged: _saveWorkoutDurationEnabled,
        onCustomExercisesChanged: () {
          if (mounted) setState(() {});
        },
        onWorkoutTemplatesChanged: _replaceWorkoutTemplates,
        onSelectedGymChanged: _setGym,
      ),
    ];
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: pages),
          ),
          if (_selectedIndex == 0) const SetkeepBannerAd(),
        ],
      ),
      bottomNavigationBar: SetkeepNavigation(
        selectedIndex: _selectedIndex,
        onSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            setState(() => _friendsRefresh++);
            unawaited(_refreshWorkoutDraft());
          }
        },
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.history,
    this.bodyWeights = const [],
    required this.selectedGym,
    required this.onGymChanged,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
    this.onBodyWeightSaved,
    this.onBodyWeightDeleted,
    required this.workoutTemplates,
    required this.onTemplateSaved,
    required this.onTemplateDeleted,
    required this.workoutDraft,
    required this.onDraftChanged,
    required this.onDraftDiscarded,
    this.inboxRepository,
    this.friendsHistoryReady = true,
    this.friendsRefresh = 0,
  });

  final List<WorkoutRecord> history;
  final List<BodyWeightEntry> bodyWeights;
  final String? selectedGym;
  final ValueChanged<String> onGymChanged;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(WorkoutRecord, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;
  final Future<void> Function(BodyWeightEntry)? onBodyWeightSaved;
  final Future<void> Function(BodyWeightEntry)? onBodyWeightDeleted;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateSaved;
  final Future<void> Function(SavedWorkoutTemplate) onTemplateDeleted;
  final WorkoutDraftSummary? workoutDraft;
  final Future<void> Function() onDraftChanged;
  final Future<void> Function() onDraftDiscarded;
  final TrainerInboxRepository? inboxRepository;
  final bool friendsHistoryReady;
  final int friendsRefresh;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => FriendsRefresh.refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            HomeHeader(
              repository: inboxRepository,
              onStart: (record) =>
                  _startWorkout(context, initialWorkout: record),
            ),
            const SizedBox(height: 24),
            if (workoutDraft != null) ...[
              ActiveWorkoutDraftCard(
                summary: workoutDraft!,
                onResume: () => _openWorkout(context, resumeDraft: true),
              ),
              const SizedBox(height: 14),
            ],
            StartWorkoutCard(
              buttonLabel: workoutDraft == null
                  ? 'トレーニングを始める'
                  : '新しいトレーニングを始める',
              onPressed: () async {
                await _startWorkout(context);
              },
            ),
            const SizedBox(height: 14),
            if (workoutTemplates.isNotEmpty) ...[
              const SizedBox(height: 24),
              const SectionTitle(title: 'マイメニュー', action: '保存したメニュー'),
              const SizedBox(height: 12),
              SavedMenusCard(
                templates: workoutTemplates,
                onSelected: (template) => _startWorkout(
                  context,
                  initialWorkout: template.toWorkoutRecord(),
                ),
                onDeleted: onTemplateDeleted,
                onRestored: onTemplateSaved,
              ),
            ],
            if (onBodyWeightSaved != null) ...[
              const SizedBox(height: 24),
              BodyWeightTrendSection(
                entries: bodyWeights,
                onSaved: onBodyWeightSaved!,
                onDeleted: onBodyWeightDeleted,
              ),
            ],
            const SizedBox(height: 24),
            FriendsSection(
              key: ValueKey(configuredFriends()?.userId),
              history: history,
              historyReady: friendsHistoryReady,
              refreshToken: friendsRefresh,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWorkout(
    BuildContext context, {
    WorkoutRecord? initialWorkout,
    bool resumeDraft = false,
  }) async {
    final place = await TrainingPlacePreference.forNewWorkout();
    if (!context.mounted) return;
    await Navigator.of(context).push<WorkoutRecord>(
      MaterialPageRoute(
        builder: (_) => WorkoutPage(
          history: history,
          initialWorkout: initialWorkout,
          initialPlace: place,
          resumeDraft: resumeDraft,
          useDefaultPlace: true,
          onSave: onWorkoutCompleted,
        ),
      ),
    );
    await onDraftChanged();
  }

  Future<void> _startWorkout(
    BuildContext context, {
    WorkoutRecord? initialWorkout,
  }) async {
    if (workoutDraft != null) {
      final canStart = await discardDraftBeforeNewWorkout(context);
      if (!canStart || !context.mounted) return;
      await onDraftDiscarded();
    }
    if (context.mounted) {
      await _openWorkout(context, initialWorkout: initialWorkout);
    }
  }
}

class _SaveWorkoutTemplateDialog extends StatefulWidget {
  const _SaveWorkoutTemplateDialog({required this.initialName});

  final String initialName;

  @override
  State<_SaveWorkoutTemplateDialog> createState() =>
      _SaveWorkoutTemplateDialogState();
}

class _SaveWorkoutTemplateDialogState
    extends State<_SaveWorkoutTemplateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('マイメニューに保存'),
      content: TextField(
        key: const Key('templateNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(
          labelText: 'メニュー名',
          hintText: '例：胸の日',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveNewTemplateNameButton'),
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class RecentMenusCard extends StatelessWidget {
  const RecentMenusCard({
    super.key,
    required this.history,
    required this.onSelected,
    required this.onSave,
  });

  final List<WorkoutRecord> history;
  final ValueChanged<WorkoutRecord> onSelected;
  final ValueChanged<WorkoutRecord> onSave;

  List<WorkoutRecord> get _recentMenus {
    final signatures = <String>{};
    final menus = <WorkoutRecord>[];
    for (final workout in history) {
      final signature = workout.exerciseGroups.keys.join('|');
      if (signatures.add(signature)) menus.add(workout);
      if (menus.length == 3) break;
    }
    return menus;
  }

  @override
  Widget build(BuildContext context) {
    final menus = _recentMenus;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: List.generate(menus.length, (index) {
          final workout = menus[index];
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                key: Key('recentMenu$index'),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryGreen,
                  child: Icon(Icons.play_arrow_rounded),
                ),
                title: Text(
                  workout.exerciseNames.map(exerciseDisplayName).join('・'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(workout.summaryLabel),
                trailing: IconButton(
                  tooltip: 'マイメニューに保存',
                  onPressed: () => onSave(workout),
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                onTap: () => onSelected(workout),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class SavedMenusCard extends StatelessWidget {
  const SavedMenusCard({
    super.key,
    required this.templates,
    required this.onSelected,
    required this.onDeleted,
    required this.onRestored,
  });

  final List<SavedWorkoutTemplate> templates;
  final ValueChanged<SavedWorkoutTemplate> onSelected;
  final Future<void> Function(SavedWorkoutTemplate) onDeleted;
  final Future<void> Function(SavedWorkoutTemplate) onRestored;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: List.generate(templates.length, (index) {
          final template = templates[index];
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                key: Key('savedMenu$index'),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF101820),
                  foregroundColor: AppColors.primaryGreen,
                  child: Icon(Icons.fitness_center_rounded),
                ),
                title: Text(
                  template.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${template.exerciseNames.map(exerciseDisplayName).join('・')} ・ ${template.sets.length}セット',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(template),
                trailing: IconButton(
                  tooltip: '${template.name}を削除',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await onDeleted(template);
                    if (context.mounted) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            duration: workoutUndoDuration,
                            persist: false,
                            content: Text('「${template.name}」を削除しました'),
                            action: SnackBarAction(
                              label: '元に戻す',
                              onPressed: () async {
                                await onRestored(template);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('「${template.name}」を元に戻しました'),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class SavedMenuManagementPage extends StatefulWidget {
  const SavedMenuManagementPage({
    super.key,
    required this.initialTemplates,
    required this.onChanged,
  });

  final List<SavedWorkoutTemplate> initialTemplates;
  final Future<void> Function(List<SavedWorkoutTemplate>) onChanged;

  @override
  State<SavedMenuManagementPage> createState() =>
      _SavedMenuManagementPageState();
}

class _SavedMenuManagementPageState extends State<SavedMenuManagementPage> {
  late List<SavedWorkoutTemplate> _templates;

  @override
  void initState() {
    super.initState();
    _templates = List<SavedWorkoutTemplate>.from(widget.initialTemplates);
  }

  Future<void> _save(List<SavedWorkoutTemplate> updated) async {
    setState(() => _templates = List<SavedWorkoutTemplate>.from(updated));
    await widget.onChanged(_templates);
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SaveWorkoutTemplateDialog(initialName: ''),
    );
    if (name == null || !mounted) return;
    if (_templates.any(
      (item) => item.name.toLowerCase() == name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同じ名前のマイメニューがあります')));
      return;
    }
    final selections = await showModalBottomSheet<List<ExerciseSelection>>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExercisePickerViewport(
        child: ExercisePickerSheet(existingNames: const {}, menus: const []),
      ),
    );
    if (selections == null || selections.isEmpty || !mounted) return;
    final ordered = await Navigator.of(context).push<List<ExerciseSelection>>(
      MaterialPageRoute(
        builder: (_) => _MenuExerciseOrderPage(
          menuName: name,
          initialExercises: selections,
        ),
      ),
    );
    if (ordered == null || !mounted) return;
    final sets = ordered
        .map((item) => _initialRecordedSet(item.template))
        .toList();
    await _save([..._templates, SavedWorkoutTemplate(name: name, sets: sets)]);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」を作成しました')));
    }
  }

  Future<void> _rename(SavedWorkoutTemplate template) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameWorkoutTemplateDialog(
        initialName: template.name,
        reservedNames: _templates
            .where((item) => item.name != template.name)
            .map((item) => item.name)
            .toSet(),
      ),
    );
    if (name == null || name == template.name) return;
    final updated = _templates
        .map(
          (item) => item.name == template.name
              ? SavedWorkoutTemplate(name: name, sets: item.sets)
              : item,
        )
        .toList();
    await _save(updated);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」に名前を変更しました')));
    }
  }

  Future<void> _delete(SavedWorkoutTemplate template) async {
    final index = _templates.indexOf(template);
    final messenger = ScaffoldMessenger.of(context);
    await _save(_templates.where((item) => item != template).toList());
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: workoutUndoDuration,
          persist: false,
          content: Text('「${template.name}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = List<SavedWorkoutTemplate>.from(_templates);
              restored.insert(index.clamp(0, restored.length), template);
              await _save(restored);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text('「${template.name}」を元に戻しました')),
                );
              }
            },
          ),
        ),
      );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final updated = List<SavedWorkoutTemplate>.from(_templates);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    await _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マイメニュー管理'),
        actions: [
          IconButton(
            key: const Key('createSavedMenuButton'),
            tooltip: '新規メニュー作成',
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _templates.isEmpty
          ? const Center(
              child: Text(
                '保存したマイメニューはありません',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator_rounded, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '右端を長押しして並び替え',
                        style: TextStyle(color: Color(0xFF6C746D)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    buildDefaultDragHandles: false,
                    itemCount: _templates.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return Card(
                        key: ValueKey('managedMenu_${template.name}'),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            template.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${template.exerciseNames.map(exerciseDisplayName).join('・')} ・ ${template.sets.length}セット',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _rename(template),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '${template.name}の名前を変更',
                                onPressed: () => _rename(template),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: '${template.name}を削除',
                                onPressed: () => _delete(template),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                              ReorderableDragStartListener(
                                key: Key('reorderMenu$index'),
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

RecordedSet _initialRecordedSet(ExerciseTemplate template) => RecordedSet(
  exerciseName: template.name,
  exerciseId: template.exerciseId,
  equipment: template.equipment,
  distanceUnit: template.distanceUnit,
  bodyPart: template.bodyPart,
  recordType: template.recordType,
  weight: template.recordType.hasWeightInput ? template.startWeight : 0,
  reps:
      template.recordType.hasWeightInput ||
          template.recordType == ExerciseRecordType.bodyweightReps
      ? template.startReps
      : 0,
  durationSeconds: template.recordType == ExerciseRecordType.timed
      ? template.startReps
      : template.recordType == ExerciseRecordType.cardio ||
            template.recordType == ExerciseRecordType.distance
      ? template.startReps * 60
      : 0,
  completed: false,
);

class _MenuExerciseOrderPage extends StatefulWidget {
  const _MenuExerciseOrderPage({
    required this.menuName,
    required this.initialExercises,
  });

  final String menuName;
  final List<ExerciseSelection> initialExercises;

  @override
  State<_MenuExerciseOrderPage> createState() => _MenuExerciseOrderPageState();
}

class _MenuExerciseOrderPageState extends State<_MenuExerciseOrderPage> {
  late final List<ExerciseSelection> _exercises = List.of(
    widget.initialExercises,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.menuName)),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('長押しして種目の順番を変更できます'),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              key: const Key('menuExerciseOrderList'),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _exercises.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _exercises.removeAt(oldIndex);
                  _exercises.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final exercise = _exercises[index].template;
                return Card(
                  key: ValueKey('menuOrder${exercise.identity}'),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle_rounded),
                    title: Text(
                      exerciseDisplayName(
                        exercise.name,
                        exerciseId: exercise.exerciseId,
                      ),
                    ),
                    subtitle: Text(
                      '${exercise.bodyPart} ・ ${exercise.equipment}',
                    ),
                    trailing: IconButton(
                      tooltip: '${exercise.name}を外す',
                      onPressed: _exercises.length == 1
                          ? null
                          : () => setState(() => _exercises.removeAt(index)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('saveCreatedMenuButton'),
                  onPressed: () => Navigator.pop(context, _exercises),
                  child: Text('${_exercises.length}種目で保存'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameWorkoutTemplateDialog extends StatefulWidget {
  const _RenameWorkoutTemplateDialog({
    required this.initialName,
    required this.reservedNames,
  });

  final String initialName;
  final Set<String> reservedNames;

  @override
  State<_RenameWorkoutTemplateDialog> createState() =>
      _RenameWorkoutTemplateDialogState();
}

class _RenameWorkoutTemplateDialogState
    extends State<_RenameWorkoutTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('メニュー名を変更'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('renameTemplateField'),
          controller: _controller,
          autofocus: true,
          maxLength: 30,
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return 'メニュー名を入力してください';
            if (widget.reservedNames.any(
              (item) => item.toLowerCase() == name.toLowerCase(),
            )) {
              return '同じ名前のメニューがあります';
            }
            return null;
          },
          decoration: const InputDecoration(labelText: 'メニュー名'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveTemplateNameButton'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.onStart,
    this.repository,
    this.friendRepository,
    this.showTrainerNotifications = trainerPublicAccessEnabled,
  });

  final Future<void> Function(WorkoutRecord) onStart;
  final TrainerInboxRepository? repository;
  final FriendCommentInboxRepository? friendRepository;
  final bool showTrainerNotifications;

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> with WidgetsBindingObserver {
  FriendCommentInboxRepository? get _friends {
    if (widget.friendRepository != null) return widget.friendRepository;
    final repo = configuredFriends();
    return repo == null ? null : FriendCommentInboxRepository(repo);
  }

  late final TrainerInboxRepository? _repository =
      widget.repository ??
      (SupabaseConfig.initialized
          ? TrainerInboxRepository(Supabase.instance.client)
          : null);
  StreamSubscription<void>? _authSubscription;
  Timer? _refreshTimer;
  int _unreadCount = 0;
  int _friendUnreadCount = 0;
  int _generation = 0;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FriendsRefresh.listen(_refresh);
    if (_repository != null || _friends != null) {
      _authSubscription = _repository?.authChanges.listen((_) {
        setState(() {
          _unreadCount = 0;
          _friendUnreadCount = 0;
        });
        unawaited(_refresh());
      });
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_active) unawaited(_refresh());
      });
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final current = ++_generation;
    final uid = _repository?.userId ?? _friends?.userId;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _unreadCount = 0;
          _friendUnreadCount = 0;
        });
      }
      return;
    }
    try {
      final count = widget.showTrainerNotifications
          ? await _repository?.unreadCount() ?? 0
          : 0;
      if (mounted &&
          current == _generation &&
          (_repository?.userId ?? _friends?.userId) == uid) {
        setState(() => _unreadCount = count);
      }
    } catch (_) {
      // A transient network error must not mark notifications as read.
    }
    try {
      final count = await _friends?.unreadCount() ?? 0;
      if (mounted &&
          current == _generation &&
          (_repository?.userId ?? _friends?.userId) == uid) {
        setState(() => _friendUnreadCount = count);
      }
    } catch (_) {
      /* Keep the last count on a transient failure. */
    }
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationSourcesPage(
          trainer: _repository,
          showTrainerNotifications: widget.showTrainerNotifications,
          friends: _friends,
          onStart: widget.onStart,
          onReadChanged: () => unawaited(_refresh()),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FriendsRefresh.unlisten(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/brand/setkeep_splash_lockup_source.png',
              key: const Key('homeBrandLogo'),
              width: 90,
              height: 46,
              fit: BoxFit.contain,
              semanticLabel: appDisplayName,
            ),
          ),
        ),
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                key: const Key('trainerInboxBell'),
                tooltip: Localizations.localeOf(context).languageCode == 'ja'
                    ? (widget.showTrainerNotifications
                          ? 'フレンド・トレーナーからの通知'
                          : 'フレンドからの通知')
                    : (widget.showTrainerNotifications
                          ? 'Notifications from friends and your trainer'
                          : 'Notifications from friends'),
                onPressed: _openInbox,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (_unreadCount + _friendUnreadCount > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    key: const Key('trainerInboxUnreadBadge'),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _unreadCount + _friendUnreadCount > 99
                          ? '99+'
                          : '${_unreadCount + _friendUnreadCount}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class StartWorkoutCard extends StatelessWidget {
  const StartWorkoutCard({
    super.key,
    required this.onPressed,
    this.buttonLabel = 'トレーニングを始める',
  });

  final VoidCallback onPressed;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '次の1セットが、\n成長の記録になる。',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 22),
          WorkoutPrimaryButton(
            key: const Key('startWorkoutButton'),
            onPressed: onPressed,
            label: buttonLabel,
          ),
        ],
      ),
    );
  }
}

class WorkoutPrimaryButton extends StatelessWidget {
  const WorkoutPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: FamilyPalette.of(context).accent,
        foregroundColor: const Color(0xFF101820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class ActiveWorkoutDraftCard extends StatelessWidget {
  const ActiveWorkoutDraftCard({
    super.key,
    required this.summary,
    required this.onResume,
  });

  final WorkoutDraftSummary summary;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('activeWorkoutDraftCard'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onResume,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primaryGreen,
                child: Icon(Icons.edit_note_rounded),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '入力途中のトレーニング',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.exerciseNames.map(exerciseDisplayName).join('・'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6C746D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workoutDateLabel(summary.date)}・${summary.setCount}セット',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777F78),
                      ),
                    ),
                  ],
                ),
              ),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded),
                  Text(
                    '再開',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action = ''});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF101820),
            ),
          ),
        ),
        if (action.isNotEmpty)
          Text(
            action,
            style: const TextStyle(
              color: Color(0xFF6C746D),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

DateTime startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

int workoutCountInWeek(List<WorkoutRecord> history, DateTime weekStart) {
  final nextWeek = weekStart.add(const Duration(days: 7));
  return history
      .where(
        (workout) =>
            !workout.date.isBefore(weekStart) &&
            workout.date.isBefore(nextWeek),
      )
      .length;
}

class WeeklySummary extends StatelessWidget {
  const WeeklySummary({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final weekStart = startOfWeek(DateTime.now());
    final nextWeek = weekStart.add(const Duration(days: 7));
    final weekly = history.where(
      (item) => !item.date.isBefore(weekStart) && item.date.isBefore(nextWeek),
    );
    final workoutCount = weekly.length;
    final volume = weekly.fold<double>(
      0,
      (total, workout) => total + workout.volume,
    );
    final historyThroughThisWeek = history
        .where((item) => item.date.isBefore(nextWeek))
        .toList();
    final personalBests = countPersonalBests(historyThroughThisWeek, weekStart);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            StatItem(value: '$workoutCount', unit: '回', label: 'ワークアウト'),
            Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            StatItem(value: formatVolumeKg(volume), unit: 'kg', label: 'ボリューム'),
            Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            StatItem(value: '$personalBests', unit: '個', label: '自己ベスト'),
          ],
        ),
      ),
    );
  }
}

class StatItem extends StatelessWidget {
  const StatItem({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF101820)),
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
          ),
        ],
      ),
    );
  }
}

class LastWorkoutCard extends StatelessWidget {
  const LastWorkoutCard({super.key, required this.workout, this.onTap});

  final WorkoutRecord? workout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (workout == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(Icons.add_chart_rounded, color: Color(0xFF6C746D)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '最初のトレーニングを記録してみよう',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final item = workout!;
    return Card(
      key: const Key('lastWorkoutCard'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  DateBadge(date: item.date),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.bodyParts.join('・'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.summaryLabel,
                          style: const TextStyle(
                            color: Color(0xFF777F78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF777F78),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: const Color(0xFFE9EBE6)),
              const SizedBox(height: 14),
              ExerciseLine(
                name: exerciseDisplayName(
                  item.highlightSet.exerciseName,
                  exerciseId: item.highlightSet.exerciseId,
                ),
                detail: item.highlightSet.displaySummary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DateBadge extends StatelessWidget {
  const DateBadge({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primaryGreenVerySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.month}月',
            style: const TextStyle(fontSize: 10, color: Color(0xFF6C746D)),
          ),
          Text(
            date.day.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class ExerciseLine extends StatelessWidget {
  const ExerciseLine({super.key, required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFC7F36B).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.fitness_center_rounded, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exerciseDisplayName(name),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Color(0xFF777F78)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MuscleChips extends StatelessWidget {
  const MuscleChips({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  Widget build(BuildContext context) {
    final counts = _bodyPartCounts(history);
    final items = ['胸', '背中', '脚', '肩', '腕', '腹'].map((part) {
      final count = counts[part] ?? 0;
      final label = count >= 5 ? '高' : (count >= 2 ? '中' : '低');
      final color = count >= 5
          ? const Color(0xFF101820)
          : (count >= 2 ? const Color(0xFF65735F) : const Color(0xFFBBC2B8));
      return (part, label, color);
    }).toList();
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.$3,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                item.$1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 7),
              Text(
                item.$2,
                style: const TextStyle(fontSize: 11, color: Color(0xFF777F78)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

Map<String, int> _bodyPartCounts(List<WorkoutRecord> history) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final counts = <String, int>{};
  for (final workout in history.where((item) => item.date.isAfter(cutoff))) {
    for (final set in workout.sets) {
      counts.update(set.bodyPart, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

int countPersonalBests(List<WorkoutRecord> history, DateTime since) {
  final bestWeights = <String, double>{};
  var count = 0;
  final chronological = [...history]..sort((a, b) => a.date.compareTo(b.date));
  for (final workout in chronological) {
    final workoutBest = <String, double>{};
    for (final set in workout.sets) {
      if (set.recordType == ExerciseRecordType.assistedReps) continue;
      workoutBest.update(
        set.identity,
        (value) => set.weight > value ? set.weight : value,
        ifAbsent: () => set.weight,
      );
    }
    for (final entry in workoutBest.entries) {
      final previous = bestWeights[entry.key] ?? 0.0;
      if (entry.value > previous) {
        bestWeights[entry.key] = entry.value;
        if (!workout.date.isBefore(since)) count++;
      }
    }
  }
  return count;
}

enum MuscleMapPeriod {
  week('1週間', 7),
  month('1ヶ月', 30),
  threeMonths('3ヶ月', 90),
  sixMonths('6ヶ月', 180),
  year('1年', 365);

  const MuscleMapPeriod(this.label, this.days);
  final String label;
  final int days;
}

Map<String, int> bodyPartSetCounts(
  List<WorkoutRecord> history,
  MuscleMapPeriod period, {
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: period.days));
  final counts = <String, int>{};
  for (final workout in history.where((item) => !item.date.isBefore(cutoff))) {
    for (final set in workout.sets.where((item) => item.completed)) {
      counts.update(set.bodyPart, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

class BodyMapPage extends StatefulWidget {
  const BodyMapPage({super.key, required this.history, this.active = true});
  final List<WorkoutRecord> history;
  final bool active;
  @override
  State<BodyMapPage> createState() => _BodyMapPageState();
}

class _BodyMapPageState extends State<BodyMapPage> {
  MuscleMapPeriod _period = MuscleMapPeriod.week;

  @override
  Widget build(BuildContext context) {
    final counts = bodyPartSetCounts(widget.history, _period);
    final muscleScores = bodyTabRelativeIntensities(counts);
    const parts = ['胸', '背中', '脚', '肩', '腕', '腹'];
    final maximum = parts.fold<int>(
      1,
      (a, part) => math.max(a, counts[part] ?? 0),
    );
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          const Text(
            '3D筋肉マネキン',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '選択期間の部位バランスを赤の濃淡で表示します',
            style: TextStyle(color: Color(0xFF6C746D)),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: MuscleMapPeriod.values
                  .map(
                    (period) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('musclePeriod${period.name}'),
                        label: Text(period.label),
                        selected: _period == period,
                        onSelected: (_) => setState(() => _period = period),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            key: const Key('muscleModel3D'),
            height: 440,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF101820),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${_period.label} ・ $totalセット',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: MuscleMannequinView(
                    key: const ValueKey('history-body-model'),
                    active: widget.active,
                    scores: muscleScores,
                    fallbackBodyPartCounts: counts,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...parts.map((part) {
            final value = counts[part] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _muscleHeatColor(value, maximum),
                  child: Text(
                    part.substring(0, 1),
                    style: const TextStyle(
                      color: Color(0xFF101820),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  part,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: LinearProgressIndicator(
                  value: value / maximum,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: const Color(0xFFE8EBE5),
                  color: _muscleHeatColor(value, maximum),
                ),
                trailing: Text(
                  '$valueセット',
                  key: Key('muscleCount$part'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum MuscleMannequinAngle {
  front('正面'),
  back('背面');

  const MuscleMannequinAngle(this.label);
  final String label;

  int get bodyViewAngle => this == front ? 0 : 2;
}

class MuscleMannequinView extends StatefulWidget {
  const MuscleMannequinView({
    super.key,
    required this.scores,
    this.fallbackBodyPartCounts = const {},
    this.active = true,
    this.tapToFlip = true,
  });

  /// Relative muscle intensities in [0, 1]; independent of period length.
  final Map<MuscleRegion, double> scores;
  final Map<String, int> fallbackBodyPartCounts;
  final bool active;
  final bool tapToFlip;

  @override
  State<MuscleMannequinView> createState() => _MuscleMannequinViewState();
}

class _MuscleMannequinViewState extends State<MuscleMannequinView> {
  final _controller = Interactive3dController();
  bool _ready = false;
  MuscleMannequinAngle _angle = MuscleMannequinAngle.front;
  int? _tapPointer;
  Offset? _tapPosition;
  DateTime? _tapStartedAt;

  void _toggleAngle() => setState(() {
    _angle = _angle == MuscleMannequinAngle.front
        ? MuscleMannequinAngle.back
        : MuscleMannequinAngle.front;
  });

  Widget _tapFrame(Widget child) {
    if (!widget.tapToFlip) return child;
    return Semantics(
      button: true,
      label: '3D筋肉マネキン',
      value: _angle.label,
      hint: 'タップして反対側を見る',
      onTap: _toggleAngle,
      child: Listener(
        key: const Key('muscleMannequinFrame'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _tapPointer = event.pointer;
          _tapPosition = event.position;
          _tapStartedAt = DateTime.now();
        },
        onPointerCancel: (_) {
          _tapPointer = null;
          _tapPosition = null;
          _tapStartedAt = null;
        },
        onPointerUp: (event) {
          final tapped =
              _tapPointer == event.pointer &&
              _tapPosition != null &&
              (event.position - _tapPosition!).distance < 12 &&
              _tapStartedAt != null &&
              DateTime.now().difference(_tapStartedAt!) <
                  const Duration(milliseconds: 450);
          _tapPointer = null;
          _tapPosition = null;
          _tapStartedAt = null;
          if (tapped) _toggleAngle();
        },
        child: child,
      ),
    );
  }

  List<MaterialOverride> get _materialOverrides {
    return [
      MaterialOverride(
        name: 'body_neutral',
        color: bodyTabMaterialColor(0),
        metallic: 0,
        roughness: 0.7,
      ),
      for (final region in MuscleRegion.values)
        MaterialOverride(
          name: 'body_${region.name}',
          color: bodyTabMaterialColor(widget.scores[region] ?? 0),
          metallic: 0,
          roughness: 0.7,
        ),
    ];
  }

  @override
  void didUpdateWidget(MuscleMannequinView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _ready = false;
    if (_ready) _controller.setEntityMaterials(_materialOverrides);
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps tab state, but a hidden platform view must be disposed.
    if (!widget.active) return const SizedBox.expand();
    if (Platform.isIOS || Platform.isAndroid) {
      return _tapFrame(
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Interactive3d(
            key: const ValueKey('body-tab-continuous'),
            controller: _controller,
            modelPath:
                '${FamilyPalette.of(context).assetPrefix}assets/models/body_tab.glb',
            formAnimation: true,
            animationPlaying: false,
            bodyViewAngle: _angle.bodyViewAngle,
            onModelReady: () {
              if (!mounted || !widget.active) return;
              _ready = true;
              _controller.setEntityMaterials(_materialOverrides);
            },
            solidBackgroundColor: const [0.035, 0.047, 0.055, 1],
            backgroundColor: const Color(0xFF091219),

            selectionColor: const [0.84, 0.03, 0.05, 1],
            initialMaterialOverrides: _materialOverrides,
            loadingWidget: const Center(
              child: CircularProgressIndicator(color: Color(0xFFE33A46)),
            ),
          ),
        ),
      );
    }

    final maximum = widget.fallbackBodyPartCounts.values.fold<int>(1, math.max);
    return _tapFrame(
      Center(
        child: CustomPaint(
          key: const Key('bodyMannequinFallback'),
          size: const Size(210, 300),
          painter: _MuscleBodyPainter(
            counts: widget.fallbackBodyPartCounts,
            maximum: maximum,
          ),
        ),
      ),
    );
  }
}

Color _muscleHeatColor(int value, int maximum) =>
    bodyTabHeatColor(maximum <= 0 ? 0 : value / maximum);

class _MuscleBodyPainter extends CustomPainter {
  const _MuscleBodyPainter({required this.counts, required this.maximum});

  final Map<String, int> counts;
  final int maximum;

  static const _wire = Color(0xFF24F4EE);
  static const _wireDim = Color(0xFF087E8C);
  static const _heat = Color(0xFFFF2638);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 230;
    final scaleY = size.height / 350;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    _paintStage(canvas);
    final body = _bodySilhouette();
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF062B38).withValues(alpha: 0.64)
        ..style = PaintingStyle.fill,
    );

    canvas.save();
    canvas.clipPath(body);
    _paintMuscleDots(canvas, body);
    _paintBodyGrid(canvas);
    canvas.restore();

    final glow = Paint()
      ..color = _wire.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final edge = Paint()
      ..color = _wire.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;
    canvas.drawPath(body, glow);
    canvas.drawPath(body, edge);
    _paintAnatomyContours(canvas);
    canvas.restore();
  }

  void _paintStage(Canvas canvas) {
    final horizon = Paint()
      ..color = _wire.withValues(alpha: 0.08)
      ..strokeWidth = 0.7;
    for (var y = 250.0; y <= 350; y += 13) {
      canvas.drawLine(Offset(8, y), Offset(222, y), horizon);
    }
    for (var x = 8.0; x <= 222; x += 18) {
      canvas.drawLine(const Offset(115, 238), Offset(x, 350), horizon);
    }
    canvas.drawOval(
      const Rect.fromLTWH(58, 337, 114, 10),
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );
  }

  Path _bodySilhouette() {
    final body = Path()
      ..addOval(const Rect.fromLTWH(94, 4, 42, 51))
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(105, 48, 20, 23),
          const Radius.circular(7),
        ),
      );

    body
      ..moveTo(99, 57)
      ..cubicTo(90, 61, 78, 63, 70, 72)
      ..cubicTo(65, 83, 66, 105, 72, 125)
      ..cubicTo(77, 142, 85, 157, 89, 176)
      ..lineTo(86, 194)
      ..cubicTo(96, 201, 106, 204, 115, 204)
      ..cubicTo(124, 204, 134, 201, 144, 194)
      ..lineTo(141, 176)
      ..cubicTo(145, 157, 153, 142, 158, 125)
      ..cubicTo(164, 105, 165, 83, 160, 72)
      ..cubicTo(152, 63, 140, 61, 131, 57)
      ..cubicTo(124, 63, 106, 63, 99, 57)
      ..close();

    _addLimb(body, const [
      Offset(72, 70),
      Offset(58, 76),
      Offset(43, 126),
      Offset(57, 132),
      Offset(78, 93),
    ]);
    _addLimb(body, const [
      Offset(43, 123),
      Offset(31, 199),
      Offset(46, 202),
      Offset(59, 130),
    ]);
    body.addOval(const Rect.fromLTWH(27, 195, 20, 31));
    _addLimb(body, const [
      Offset(158, 70),
      Offset(172, 76),
      Offset(187, 126),
      Offset(173, 132),
      Offset(152, 93),
    ]);
    _addLimb(body, const [
      Offset(187, 123),
      Offset(199, 199),
      Offset(184, 202),
      Offset(171, 130),
    ]);
    body.addOval(const Rect.fromLTWH(183, 195, 20, 31));

    _addLimb(body, const [
      Offset(88, 183),
      Offset(114, 188),
      Offset(108, 256),
      Offset(97, 276),
      Offset(77, 271),
      Offset(80, 228),
    ]);
    _addLimb(body, const [
      Offset(77, 263),
      Offset(99, 266),
      Offset(93, 326),
      Offset(75, 327),
      Offset(69, 294),
    ]);
    _addLimb(body, const [
      Offset(142, 183),
      Offset(116, 188),
      Offset(122, 256),
      Offset(133, 276),
      Offset(153, 271),
      Offset(150, 228),
    ]);
    _addLimb(body, const [
      Offset(153, 263),
      Offset(131, 266),
      Offset(137, 326),
      Offset(155, 327),
      Offset(161, 294),
    ]);
    _addLimb(body, const [
      Offset(75, 320),
      Offset(94, 320),
      Offset(98, 339),
      Offset(65, 339),
      Offset(66, 331),
    ]);
    _addLimb(body, const [
      Offset(155, 320),
      Offset(136, 320),
      Offset(132, 339),
      Offset(165, 339),
      Offset(164, 331),
    ]);
    return body;
  }

  void _addLimb(Path path, List<Offset> points) {
    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
  }

  void _paintBodyGrid(Canvas canvas) {
    final fine = Paint()
      ..color = _wire.withValues(alpha: 0.54)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55;
    final strong = Paint()
      ..color = _wire.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.78;

    for (var y = 7.0; y < 340; y += 5.5) {
      final bend = math.sin(y / 19) * 3.2;
      final path = Path()
        ..moveTo(20, y)
        ..quadraticBezierTo(115 + bend, y + 2.6, 210, y);
      canvas.drawPath(path, ((y / 5.5).round().isEven) ? strong : fine);
    }
    for (var x = 30.0; x <= 200; x += 6.5) {
      final distance = (x - 115) / 100;
      final path = Path()
        ..moveTo(x, 0)
        ..cubicTo(
          x + distance * 8,
          92,
          x - distance * 7,
          246,
          x + distance * 5,
          345,
        );
      canvas.drawPath(path, ((x / 6.5).round().isEven) ? strong : fine);
    }

    final face = Paint()
      ..color = _wire.withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (var i = 1; i < 7; i++) {
      final top = 5 + i * 6.5;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(115, top),
          width: 38 - (top - 28).abs() * 0.32,
          height: 6.5,
        ),
        face,
      );
    }
    for (final dx in [-13.0, -7.0, 0.0, 7.0, 13.0]) {
      final path = Path()
        ..moveTo(115 + dx * 0.35, 5)
        ..quadraticBezierTo(115 + dx * 1.2, 29, 115 + dx * 0.55, 54);
      canvas.drawPath(path, face);
    }
  }

  void _paintMuscleDots(Canvas canvas, Path body) {
    final regions = <String, List<Path>>{
      '肩': [
        Path()..addOval(const Rect.fromLTWH(65, 65, 31, 34)),
        Path()..addOval(const Rect.fromLTWH(134, 65, 31, 34)),
      ],
      '腕': [
        Path()..addOval(const Rect.fromLTWH(49, 85, 24, 49)),
        Path()..addOval(const Rect.fromLTWH(157, 85, 24, 49)),
        Path()..addOval(const Rect.fromLTWH(32, 133, 20, 67)),
        Path()..addOval(const Rect.fromLTWH(178, 133, 20, 67)),
      ],
      '脚': [
        Path()..addOval(const Rect.fromLTWH(78, 190, 35, 85)),
        Path()..addOval(const Rect.fromLTWH(117, 190, 35, 85)),
        Path()..addOval(const Rect.fromLTWH(70, 267, 29, 61)),
        Path()..addOval(const Rect.fromLTWH(131, 267, 29, 61)),
      ],
      '胸': [
        Path()..addOval(const Rect.fromLTWH(80, 74, 34, 52)),
        Path()..addOval(const Rect.fromLTWH(116, 74, 34, 52)),
      ],
      '腹': [
        Path()..addRRect(const RRect.fromLTRBXY(96, 126, 134, 190, 13, 13)),
      ],
    };

    for (final entry in regions.entries) {
      final value = counts[entry.key] ?? 0;
      if (value <= 0) continue;
      final intensity = (value / maximum).clamp(0.0, 1.0);
      final spacing = 7.5 - intensity * 3.2;
      final dotPaint = Paint()
        ..color = _heat.withValues(alpha: 0.48 + intensity * 0.46)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 + intensity);
      for (final region in entry.value) {
        final bounds = region.getBounds();
        for (var y = bounds.top; y <= bounds.bottom; y += spacing) {
          for (var x = bounds.left; x <= bounds.right; x += spacing) {
            final staggeredX =
                x + ((y / spacing).round().isEven ? 0 : spacing / 2);
            final point = Offset(staggeredX, y);
            if (region.contains(point) && body.contains(point)) {
              canvas.drawCircle(point, 0.85 + intensity * 0.65, dotPaint);
            }
          }
        }
      }
    }
  }

  void _paintAnatomyContours(Canvas canvas) {
    final contour = Paint()
      ..color = _wireDim.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final bright = Paint()
      ..color = _wire.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.72;

    canvas.drawLine(const Offset(115, 58), const Offset(115, 202), contour);
    canvas.drawArc(
      const Rect.fromLTWH(79, 67, 72, 39),
      0.1,
      2.95,
      false,
      bright,
    );
    canvas.drawArc(
      const Rect.fromLTWH(84, 111, 62, 68),
      0.15,
      2.85,
      false,
      contour,
    );
    canvas.drawArc(
      const Rect.fromLTWH(83, 177, 64, 28),
      0,
      math.pi,
      false,
      bright,
    );
    canvas.drawLine(const Offset(114, 202), const Offset(108, 257), contour);
    canvas.drawLine(const Offset(116, 202), const Offset(122, 257), contour);
    canvas.drawOval(const Rect.fromLTWH(105, 23, 8, 4), bright);
    canvas.drawOval(const Rect.fromLTWH(117, 23, 8, 4), bright);
    canvas.drawArc(
      const Rect.fromLTWH(107, 34, 16, 8),
      0,
      math.pi,
      false,
      bright,
    );
  }

  @override
  bool shouldRepaint(covariant _MuscleBodyPainter old) =>
      old.counts != counts || old.maximum != maximum;
}

class MonthlyHistoryPage extends StatefulWidget {
  const MonthlyHistoryPage({
    super.key,
    required this.history,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(WorkoutRecord, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  State<MonthlyHistoryPage> createState() => _MonthlyHistoryPageState();
}

class _MonthlyHistoryPageState extends State<MonthlyHistoryPage> {
  final ScrollController _scrollController = ScrollController();
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _moveMonth(int amount) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + amount,
      );
      _selectedDay = null;
    });
  }

  void _showCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDay = null;
    });
  }

  void _selectDay(DateTime date, bool selected) {
    setState(() => _selectedDay = selected ? null : date);
    if (selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent.clamp(
        0.0,
        460.0,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monthWorkouts = widget.history
        .where(
          (workout) =>
              workout.date.year == _visibleMonth.year &&
              workout.date.month == _visibleMonth.month,
        )
        .toList();
    final shownWorkouts = _selectedDay == null
        ? monthWorkouts
        : monthWorkouts
              .where((workout) => _sameDay(workout.date, _selectedDay!))
              .toList();
    final volume = monthWorkouts.fold<double>(
      0,
      (total, workout) => total + workout.volume,
    );
    final setCount = monthWorkouts.fold<int>(
      0,
      (total, workout) =>
          total + workout.sets.where((set) => set.recordType.usesSets).length,
    );
    final today = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == today.year && _visibleMonth.month == today.month;

    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '月間カレンダー',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
        ),
        actions: [
          if (widget.history.isNotEmpty)
            IconButton(
              tooltip: '履歴を検索',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HistorySearchPage(
                    history: widget.history,
                    selectedGym: widget.selectedGym,
                    onWorkoutCompleted: widget.onWorkoutCompleted,
                    onWorkoutUpdated: widget.onWorkoutUpdated,
                    onWorkoutDeleted: widget.onWorkoutDeleted,
                  ),
                ),
              ),
              icon: const Icon(Icons.search_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '前の月',
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${_visibleMonth.year}年 ${_visibleMonth.month}月',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '次の月',
                onPressed: isCurrentMonth ? null : () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          if (!isCurrentMonth)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                key: const Key('historyCurrentMonthButton'),
                onPressed: _showCurrentMonth,
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('今月に戻る'),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  StatItem(
                    value: '${monthWorkouts.length}',
                    unit: '回',
                    label: 'トレーニング数',
                  ),
                  Container(
                    width: 1,
                    height: 46,
                    color: const Color(0xFFE4E7E1),
                  ),
                  StatItem(value: '$setCount', unit: 'セット', label: 'セット数'),
                  Container(
                    width: 1,
                    height: 46,
                    color: const Color(0xFFE4E7E1),
                  ),
                  StatItem(
                    value: formatVolumeKg(volume),
                    unit: 'kg',
                    label: '総ボリューム',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          WorkoutMonthCalendar(
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            recordedDates: monthWorkouts.map((workout) => workout.date),
            onSelectDay: _selectDay,
          ),
          const SizedBox(height: 22),
          Text(
            _selectedDay == null
                ? 'この月の記録'
                : '${_selectedDay!.month}月${_selectedDay!.day}日の記録',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (shownWorkouts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _selectedDay == null ? 'この月の記録はありません' : 'この日の記録はありません',
                  style: const TextStyle(color: Color(0xFF6C746D)),
                ),
              ),
            )
          else
            ...shownWorkouts.map(
              (workout) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HistoryCard(
                  workout: workout,
                  selectedGym: widget.selectedGym,
                  onWorkoutCompleted: widget.onWorkoutCompleted,
                  onWorkoutUpdated: widget.onWorkoutUpdated,
                  onWorkoutDeleted: widget.onWorkoutDeleted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BodyWeightTrendSection extends StatefulWidget {
  const BodyWeightTrendSection({
    super.key,
    required this.entries,
    required this.onSaved,
    this.onDeleted,
  });

  final List<BodyWeightEntry> entries;
  final Future<void> Function(BodyWeightEntry) onSaved;
  final Future<void> Function(BodyWeightEntry)? onDeleted;

  @override
  State<BodyWeightTrendSection> createState() => _BodyWeightTrendSectionState();
}

class _BodyWeightTrendSectionState extends State<BodyWeightTrendSection> {
  BodyWeightPeriod _period = BodyWeightPeriod.oneMonth;
  String? _selectedId;

  @override
  void didUpdateWidget(covariant BodyWeightTrendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedId != null &&
        !widget.entries.any((entry) => entry.id == _selectedId)) {
      _selectedId = null;
    }
  }

  Future<void> _edit([BodyWeightEntry? initial]) async {
    final result = await showDialog<BodyWeightEntry>(
      context: context,
      builder: (_) =>
          BodyWeightEditorDialog(initial: initial, onDeleted: widget.onDeleted),
    );
    if (result == null) return;
    await widget.onSaved(result);
    if (mounted) setState(() => _selectedId = result.id);
  }

  @override
  Widget build(BuildContext context) {
    final entries = bodyWeightsForPeriod(widget.entries, _period);
    BodyWeightEntry? selected;
    for (final entry in entries) {
      if (entry.id == _selectedId) selected = entry;
    }
    final recent = sortBodyWeights(widget.entries).reversed.take(1).toList();
    return Card(
      key: const Key('bodyWeightTrendSection'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '体重推移',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('addBodyWeightButton'),
                  onPressed: _edit,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('記録'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: BodyWeightPeriod.values
                    .map(
                      (period) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: Key('bodyWeightPeriod${period.months}'),
                          label: Text(period.label),
                          selected: _period == period,
                          onSelected: (_) => setState(() {
                            _period = period;
                            _selectedId = null;
                          }),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              Container(
                height: 156,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monitor_weight_outlined, size: 30),
                    SizedBox(height: 8),
                    Text('体重を記録するとグラフが表示されます'),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  key: const Key('bodyWeightChart'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final index = _nearestBodyWeightPoint(
                      entries,
                      details.localPosition.dx,
                      constraints.maxWidth,
                    );
                    setState(() => _selectedId = entries[index].id);
                  },
                  child: CustomPaint(
                    painter: BodyWeightChartPainter(
                      entries: entries,
                      selectedId: _selectedId,
                    ),
                    size: Size(constraints.maxWidth, 190),
                  ),
                ),
              ),
            if (selected != null &&
                (recent.isEmpty || selected.id != recent.first.id)) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('selectedBodyWeight'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreenSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_bodyWeightDate(selected.recordedAt)}  ${_bodyWeightLabel(selected.weightKg)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _edit(selected),
                      child: const Text('編集'),
                    ),
                  ],
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              ...recent.map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_bodyWeightDate(entry.recordedAt)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_bodyWeightLabel(entry.weightKg)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      IconButton(
                        key: Key('editBodyWeight${entry.id}'),
                        tooltip: '体重を編集',
                        onPressed: () => _edit(entry),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

int _nearestBodyWeightPoint(
  List<BodyWeightEntry> entries,
  double tapX,
  double width,
) {
  if (entries.length <= 1) return 0;
  const left = 46.0;
  const right = 12.0;
  final usable = math.max(1, width - left - right);
  final start = entries.first.recordedAt.millisecondsSinceEpoch;
  final end = entries.last.recordedAt.millisecondsSinceEpoch;
  if (start == end) {
    return ((tapX - left) / usable * (entries.length - 1)).round().clamp(
      0,
      entries.length - 1,
    );
  }
  var best = 0;
  var distance = double.infinity;
  for (var index = 0; index < entries.length; index++) {
    final ratio =
        (entries[index].recordedAt.millisecondsSinceEpoch - start) /
        (end - start);
    final pointDistance = (left + ratio * usable - tapX).abs();
    if (pointDistance < distance) {
      distance = pointDistance;
      best = index;
    }
  }
  return best;
}

String _bodyWeightDate(DateTime date) =>
    '${date.year}/${date.month}/${date.day}';

String _bodyWeightLabel(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

class BodyWeightEditorDialog extends StatefulWidget {
  const BodyWeightEditorDialog({super.key, this.initial, this.onDeleted});

  final BodyWeightEntry? initial;
  final Future<void> Function(BodyWeightEntry)? onDeleted;

  @override
  State<BodyWeightEditorDialog> createState() => _BodyWeightEditorDialogState();
}

class _BodyWeightEditorDialogState extends State<BodyWeightEditorDialog> {
  late DateTime _date;
  late final TextEditingController _controller;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initial?.recordedAt ?? DateTime.now();
    _controller = TextEditingController(
      text: widget.initial == null
          ? ''
          : _bodyWeightLabel(widget.initial!.weightKg),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected == null) return;
    setState(() {
      _date = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _date.hour,
        _date.minute,
        _date.second,
        _date.millisecond,
        _date.microsecond,
      );
    });
  }

  Future<void> _delete() async {
    if (_deleting || widget.initial == null || widget.onDeleted == null) return;
    setState(() => _deleting = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この体重記録を削除しますか？'),
        actions: [
          TextButton(
            key: const Key('cancelDeleteBodyWeightButton'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const Key('confirmDeleteBodyWeightButton'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _deleting = false);
      return;
    }
    try {
      await widget.onDeleted!(widget.initial!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = '削除できませんでした。もう一度お試しください。';
        });
      }
    }
  }

  void _save() {
    if (_deleting) return;
    final weight = double.tryParse(
      _controller.text.trim().replaceAll(',', '.'),
    );
    if (weight == null || !weight.isFinite || weight <= 0) {
      setState(() => _error = '体重を正しく入力してください');
      return;
    }
    Navigator.pop(
      context,
      BodyWeightEntry(
        id:
            widget.initial?.id ??
            '${_date.toIso8601String()}_${DateTime.now().microsecondsSinceEpoch}',
        recordedAt: _date,
        weightKg: weight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '体重を記録' : '体重を編集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            key: const Key('bodyWeightDateButton'),
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_bodyWeightDate(_date)),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bodyWeightField'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '体重',
              suffixText: 'kg',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null && widget.onDeleted != null)
          TextButton(
            key: const Key('deleteBodyWeightButton'),
            onPressed: _deleting ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB3261E),
            ),
            child: const Text('削除'),
          ),
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveBodyWeightButton'),
          onPressed: _deleting ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class BodyWeightChartPainter extends CustomPainter {
  const BodyWeightChartPainter({required this.entries, this.selectedId});

  final List<BodyWeightEntry> entries;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    const left = 46.0;
    const right = 12.0;
    const top = 14.0;
    const bottom = 28.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final values = entries.map((entry) => entry.weightKg);
    var minWeight = values.reduce(math.min);
    var maxWeight = values.reduce(math.max);
    if ((maxWeight - minWeight).abs() < 0.1) {
      minWeight -= 1;
      maxWeight += 1;
    } else {
      final padding = (maxWeight - minWeight) * 0.18;
      minWeight -= padding;
      maxWeight += padding;
    }
    final gridPaint = Paint()
      ..color = const Color(0xFFE4E7E1)
      ..strokeWidth = 1;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var index = 0; index < 3; index++) {
      final ratio = index / 2;
      final y = chart.bottom - ratio * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = minWeight + ratio * (maxWeight - minWeight);
      labelPainter.text = TextSpan(
        text: value.toStringAsFixed(1),
        style: const TextStyle(fontSize: 9, color: Color(0xFF777F78)),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(0, y - labelPainter.height / 2));
    }
    final start = entries.first.recordedAt.millisecondsSinceEpoch;
    final end = entries.last.recordedAt.millisecondsSinceEpoch;
    Offset position(int index) {
      final timeRatio = end == start
          ? (entries.length == 1 ? 0.5 : index / (entries.length - 1))
          : (entries[index].recordedAt.millisecondsSinceEpoch - start) /
                (end - start);
      final weightRatio =
          (entries[index].weightKg - minWeight) / (maxWeight - minWeight);
      return Offset(
        chart.left + timeRatio * chart.width,
        chart.bottom - weightRatio * chart.height,
      );
    }

    final path = Path()..moveTo(position(0).dx, position(0).dy);
    for (var index = 1; index < entries.length; index++) {
      final point = position(index);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primaryGreenStrong
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    for (var index = 0; index < entries.length; index++) {
      final selected = entries[index].id == selectedId;
      canvas.drawCircle(
        position(index),
        selected ? 6 : 4,
        Paint()
          ..color = selected
              ? const Color(0xFFD94747)
              : const Color(0xFF101820),
      );
    }
    for (final index in {0, entries.length - 1}) {
      labelPainter.text = TextSpan(
        text:
            '${entries[index].recordedAt.month}/${entries[index].recordedAt.day}',
        style: const TextStyle(fontSize: 9, color: Color(0xFF777F78)),
      );
      labelPainter.layout();
      final x = position(index).dx - (index == 0 ? 0 : labelPainter.width);
      labelPainter.paint(canvas, Offset(x, chart.bottom + 8));
    }
  }

  @override
  bool shouldRepaint(covariant BodyWeightChartPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.selectedId != selectedId;
  }
}

class HistorySearchPage extends StatefulWidget {
  const HistorySearchPage({
    super.key,
    required this.history,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final List<WorkoutRecord> history;
  final String? selectedGym;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(WorkoutRecord, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  State<HistorySearchPage> createState() => _HistorySearchPageState();
}

bool workoutMatchesQuery(WorkoutRecord workout, String query) {
  final normalized = _normalizeWorkoutSearchText(query);
  if (normalized.isEmpty) return true;
  final date = workout.date;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final searchable = [
    ...workout.exerciseNames,
    for (final set in workout.sets) ...[
      set.exerciseName,
      ...?ExerciseFormCatalog.canonicalDefinition(set.exerciseId)?.aliases,
      ExerciseFormCatalog.canonicalDefinition(set.exerciseId)?.englishName ??
          '',
    ],
    ...workout.bodyParts,
    workout.gymName ?? '',
    workout.note,
    '${date.year}年${date.month}月${date.day}日',
    '${date.year}/${date.month}/${date.day}',
    '${date.year}-$month-$day',
    '${date.month}/${date.day}',
  ].join(' ');
  return _normalizeWorkoutSearchText(searchable).contains(normalized);
}

String _normalizeWorkoutSearchText(String value) {
  const fullWidthDigits = '０１２３４５６７８９';
  var normalized = value.trim().toLowerCase();
  for (var index = 0; index < fullWidthDigits.length; index++) {
    normalized = normalized.replaceAll(fullWidthDigits[index], '$index');
  }
  return normalized
      .replaceAll('／', '/')
      .replaceAll('・', '/')
      .replaceAll('-', '/');
}

class _HistorySearchPageState extends State<HistorySearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  late List<WorkoutRecord> _history = List.of(widget.history);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _history
        .where((workout) => workoutMatchesQuery(workout, _query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text('履歴を検索'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          children: [
            TextField(
              key: const Key('historySearchField'),
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: '種目・部位・場所・メモ・日付',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '検索をクリア',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isEmpty
                    ? '全${results.length}件'
                    : '${results.length}件の記録',
                key: const Key('historySearchResultCount'),
                style: const TextStyle(
                  color: Color(0xFF6C746D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('該当する記録はありません'))
                  : ListView.separated(
                      itemCount: results.length,
                      padding: const EdgeInsets.only(bottom: 32),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => HistoryCard(
                        workout: results[index],
                        selectedGym: widget.selectedGym,
                        onWorkoutCompleted: (workout) async {
                          await widget.onWorkoutCompleted(workout);
                          if (mounted) {
                            setState(
                              () => _history = sortWorkoutsNewestFirst([
                                workout,
                                ..._history.where(
                                  (w) => !_sameWorkout(w, workout),
                                ),
                              ]),
                            );
                          }
                        },
                        onWorkoutUpdated: (original, updated) async {
                          await widget.onWorkoutUpdated(original, updated);
                          if (mounted) {
                            setState(
                              () => _history = sortWorkoutsNewestFirst([
                                if (updated.sets.isNotEmpty) updated,
                                ..._history.where(
                                  (w) => !_sameWorkout(w, original),
                                ),
                              ]),
                            );
                          }
                        },
                        onWorkoutDeleted: (workout) async {
                          final deleted = await widget.onWorkoutDeleted(
                            workout,
                          );
                          if (deleted && mounted) {
                            setState(
                              () => _history.removeWhere(
                                (w) => _sameWorkout(w, workout),
                              ),
                            );
                          }
                          return deleted;
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseProgressPage extends StatefulWidget {
  const ExerciseProgressPage({super.key, required this.history});

  final List<WorkoutRecord> history;

  @override
  State<ExerciseProgressPage> createState() => _ExerciseProgressPageState();
}

class _ExerciseProgressPageState extends State<ExerciseProgressPage> {
  late String _selectedExercise;

  List<String> get _exerciseNames {
    final names = widget.history
        .expand((workout) => workout.exerciseGroups.keys)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  String _labelForIdentity(String key) {
    final set = widget.history
        .expand((w) => w.sets)
        .firstWhere((s) => s.identity == key);
    return '${exerciseDisplayName(set.exerciseName, exerciseId: set.exerciseId)}${set.equipment.isEmpty ? '' : ' ・ ${set.equipment}'}';
  }

  @override
  void initState() {
    super.initState();
    _selectedExercise = _exerciseNames.first;
  }

  List<_ExerciseProgressPoint> get _points {
    final points = <_ExerciseProgressPoint>[];
    for (final workout in widget.history.reversed) {
      final sets = workout.sets
          .where((set) => set.identity == _selectedExercise)
          .toList();
      if (sets.isEmpty) continue;
      final bestWeight = sets.fold<double>(
        0.0,
        (best, set) => set.weight > best ? set.weight : best,
      );
      final estimatedOneRepMax = sets.fold<double>(0, (best, set) {
        final estimate = set.weight * (1 + set.reps / 30);
        return estimate > best ? estimate : best;
      });
      points.add(
        _ExerciseProgressPoint(
          date: workout.date,
          bestWeight: bestWeight,
          estimatedOneRepMax: estimatedOneRepMax,
          setCount: sets.length,
        ),
      );
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final selectedSets = widget.history
        .expand((w) => w.sets)
        .where((s) => s.identity == _selectedExercise);
    if (selectedSets.any(
          (s) => s.recordType == ExerciseRecordType.assistedReps,
        ) ||
        selectedSets.any(
          (s) => usesAssistanceWeight(s.exerciseName, exerciseId: s.exerciseId),
        )) {
      return Scaffold(
        appBar: AppBar(title: const Text('種目ごとの成長')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedExercise,
              items: _exerciseNames
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      child: Text(_labelForIdentity(id)),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) setState(() => _selectedExercise = id);
              },
            ),
            const SizedBox(height: 16),
            const Text('補助重量は軽いほど負荷が高くなります。総ボリューム・最高重量・推定1RMには含めません。'),
            for (final workout in widget.history)
              for (final set in workout.sets.where(
                (s) => s.identity == _selectedExercise,
              ))
                ListTile(
                  title: Text(set.displaySummary),
                  subtitle: Text(
                    '${workout.date.year}/${workout.date.month}/${workout.date.day}${set.recordType == ExerciseRecordType.bodyweightReps ? ' ・ 補助重量未記録' : ''}',
                  ),
                ),
          ],
        ),
      );
    }
    final points = _points;
    final bestWeight = points.fold<double>(
      0.0,
      (best, point) => point.bestWeight > best ? point.bestWeight : best,
    );
    final estimatedOneRepMax = points.fold<double>(
      0,
      (best, point) =>
          point.estimatedOneRepMax > best ? point.estimatedOneRepMax : best,
    );
    final totalSets = points.fold<int>(
      0,
      (total, point) => total + point.setCount,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text('種目ごとの成長'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedExercise,
            decoration: const InputDecoration(
              labelText: '種目',
              border: OutlineInputBorder(),
            ),
            items: _exerciseNames
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(_labelForIdentity(name)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedExercise = value);
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ProgressMetric(
                  label: '最高重量',
                  value: '${formatWeight(bestWeight)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProgressMetric(
                  label: '推定1RM',
                  value: '${estimatedOneRepMax.round()} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProgressMetric(label: '総セット', value: '$totalSets'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ExerciseProgressChart(points: points),
          const SizedBox(height: 24),
          const Text(
            '記録一覧',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...points.reversed.map(
            (point) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primaryGreen,
                  child: Icon(Icons.fitness_center_rounded),
                ),
                title: Text(
                  '${formatWeight(point.bestWeight)} kg',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${point.date.month}月${point.date.day}日 ・ ${point.setCount}セット',
                ),
                trailing: Text(
                  '1RM ${point.estimatedOneRepMax.round()} kg',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseProgressPoint {
  const _ExerciseProgressPoint({
    required this.date,
    required this.bestWeight,
    required this.estimatedOneRepMax,
    required this.setCount,
  });

  final DateTime date;
  final double bestWeight;
  final double estimatedOneRepMax;
  final int setCount;
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6C746D)),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseProgressChart extends StatelessWidget {
  const _ExerciseProgressChart({required this.points});

  final List<_ExerciseProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final visible = points.length > 8
        ? points.sublist(points.length - 8)
        : points;
    final maximum = visible.fold<double>(
      1.0,
      (best, point) => point.bestWeight > best ? point.bestWeight : best,
    );
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最高重量の変化',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: visible.map((point) {
                return Expanded(
                  child: Semantics(
                    label:
                        '${point.date.month}月${point.date.day}日、${formatWeight(point.bestWeight)} kg',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            formatWeight(point.bestWeight),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: 18 + (70 * point.bestWeight / maximum),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${point.date.day}日',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.workout,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final WorkoutRecord workout;
  final String? selectedGym;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(WorkoutRecord, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final deleted = await Navigator.of(context).push<WorkoutRecord>(
            MaterialPageRoute<WorkoutRecord>(
              builder: (_) => WorkoutDetailPage(
                workout: workout,
                selectedGym: selectedGym,
                onWorkoutCompleted: onWorkoutCompleted,
                onWorkoutUpdated: onWorkoutUpdated,
                onWorkoutDeleted: onWorkoutDeleted,
              ),
            ),
          );
          if (deleted != null) {
            _showDeletedWorkoutUndo(messenger, deleted, onWorkoutCompleted);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              DateBadge(date: workout.date),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.exerciseNames.length == 1
                          ? workout.exerciseNames.first
                          : '${workout.exerciseNames.first} ほか${workout.exerciseNames.length - 1}種目',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      workout.summaryLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777F78),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      workout.highlightSet.displaySummary,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (workout.gymName != null &&
                        workout.gymName!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Color(0xFF777F78),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              workout.gymName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777F78),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (workout.note.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.notes_rounded,
                            size: 14,
                            color: Color(0xFF777F78),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              workout.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777F78),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF777F78)),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameWorkout(WorkoutRecord a, WorkoutRecord b) =>
    a.trainerWorkoutId != null || b.trainerWorkoutId != null
    ? a.trainerWorkoutId == b.trainerWorkoutId &&
          a.trainerOwnerUserId == b.trainerOwnerUserId
    : a.date == b.date;

const workoutUndoDuration = Duration(seconds: 2);

void _showDeletedWorkoutUndo(
  ScaffoldMessengerState messenger,
  WorkoutRecord workout,
  Future<void> Function(WorkoutRecord) onRestore,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: workoutUndoDuration,
        persist: false,
        content: const Text('トレーニング記録を削除しました'),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () async {
            try {
              await onRestore(workout);
            } catch (_) {
              messenger.showSnackBar(
                const SnackBar(content: Text('復元できませんでした。通信状態を確認してください')),
              );
              return;
            }
            if (!messenger.mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('トレーニング記録を元に戻しました')),
            );
          },
        ),
      ),
    );
}

class _WorkoutDetailSummary extends StatelessWidget {
  const _WorkoutDetailSummary({required this.workout});
  final WorkoutRecord workout;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('種目数', '${workout.exerciseNames.length} 種目'),
      (
        'セット数',
        '${workout.sets.where((set) => set.recordType.usesSets).length} セット',
      ),
      ('総ボリューム', '${formatVolumeKg(workout.volume)} kg'),
      if (WorkoutUiPreference.workoutDurationEnabled &&
          workout.durationLabel.isNotEmpty)
        ('トレーニング時間', workout.durationLabel),
    ];
    return Container(
      key: const Key('workoutDetailSummary'),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Container(width: 1, height: 46, color: const Color(0xFFE4E7E1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: Key('detailSummaryValue${items[index].$1}'),
                      height: 28,
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          items[index].$2,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF101820),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        items[index].$1,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF777F78),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({
    super.key,
    required this.workout,
    required this.selectedGym,
    required this.onWorkoutCompleted,
    required this.onWorkoutUpdated,
    required this.onWorkoutDeleted,
  });

  final WorkoutRecord workout;
  final String? selectedGym;
  final Future<void> Function(WorkoutRecord) onWorkoutCompleted;
  final Future<void> Function(WorkoutRecord, WorkoutRecord) onWorkoutUpdated;
  final Future<bool> Function(WorkoutRecord) onWorkoutDeleted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F0),
        title: const Text(
          'トレーニング詳細',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            key: const Key('openWorkoutShareButton'),
            tooltip: 'SNS用画像を作る',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => WorkoutSharePage(workout: workout),
              ),
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                final updated = await Navigator.of(context).push<WorkoutRecord>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      initialWorkout: workout,
                      isEditing: true,
                      gymName: workout.gymName ?? selectedGym,
                      onSave: (updated) => onWorkoutUpdated(workout, updated),
                    ),
                  ),
                );
                if (updated != null && context.mounted) Navigator.pop(context);
              }
              if (value == 'delete' && context.mounted) {
                await _confirmDelete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('記録を修正')),
              PopupMenuItem(value: 'delete', child: Text('記録を削除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            '${workout.date.year}年${workout.date.month}月${workout.date.day}日',
            style: const TextStyle(color: Color(0xFF6C746D)),
          ),
          if (workout.gymName != null && workout.gymName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Color(0xFF6C746D),
                ),
                const SizedBox(width: 4),
                Text(
                  workout.gymName!,
                  style: const TextStyle(color: Color(0xFF6C746D)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _WorkoutDetailSummary(workout: workout),
          if (workout.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (workout.trainerWorkoutId != null) ...[
                    const Text(
                      'トレーナーからのコメント',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          workout.note,
                          style: const TextStyle(color: Color(0xFF6C746D)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          ...workout.exerciseGroups.values.map((sets) {
            final name = exerciseDisplayName(
              sets.first.exerciseName,
              exerciseId: sets.first.exerciseId,
            );
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sets.first.bodyPart}${sets.first.equipment.isEmpty ? '' : ' ・ ${sets.first.equipment}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777F78),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(
                      sets.length,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                sets[index].displaySummary,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primaryGreenStrong,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              key: const Key('repeatWorkoutButton'),
              onPressed: () async {
                final canStart = await discardDraftBeforeNewWorkout(context);
                if (!canStart || !context.mounted) return;
                final place = await TrainingPlacePreference.forNewWorkout();
                if (!context.mounted) return;
                await Navigator.of(context).push<WorkoutRecord>(
                  MaterialPageRoute(
                    builder: (_) => WorkoutPage(
                      history: [workout],
                      initialWorkout: workout,
                      initialPlace: place,
                      useDefaultPlace: true,
                      resumeDraft: false,
                      onSave: onWorkoutCompleted,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('この内容でもう一度'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: const Text('削除後も直後なら元に戻せます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await onWorkoutDeleted(workout);
    if (!context.mounted) return;
    if (deleted) {
      Navigator.pop(context, workout);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クラウドとの通信に失敗したため削除できませんでした')),
      );
    }
  }
}

class WorkoutSharePage extends StatefulWidget {
  const WorkoutSharePage({
    super.key,
    required this.workout,
    this.completionFlow = false,
    this.completionAd,
  });

  final WorkoutRecord workout;
  final bool completionFlow;
  final WorkoutInterstitialSession? completionAd;

  @override
  State<WorkoutSharePage> createState() => _WorkoutSharePageState();
}

class _WorkoutSharePageState extends State<WorkoutSharePage> {
  final GlobalKey _previewKey = GlobalKey();
  Uint8List? _backgroundBytes;
  bool _sharing = false;
  bool _leaving = false;

  Future<void> _leaveCompletedShare() async {
    if (_leaving || !widget.completionFlow) return;
    _leaving = true;
    await widget.completionAd?.tryShow();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.completionAd?.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await image_picker.ImagePicker().pickImage(
        source: image_picker.ImageSource.gallery,
        maxWidth: 2160,
        imageQuality: 92,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _backgroundBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('写真を読み込めませんでした')));
    }
  }

  Future<void> _saveImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    var saved = false;
    try {
      late final Uint8List bytes;
      if (WorkoutImageService.captureOverride case final capture?) {
        bytes = await capture();
      } else {
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            _previewKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('preview not ready');
        final image = await boundary.toImage(pixelRatio: 3);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('image conversion failed');
          bytes = data.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }
      if (!mounted) return;
      await WorkoutImageService.save(bytes);
      saved = true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('画像を写真へ保存しました')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('画像を保存できませんでした')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
    if (saved && mounted && widget.completionFlow) {
      await _leaveCompletedShare();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.completionFlow,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leaveCompletedShare());
      },
      child: _buildShareScaffold(context),
    );
  }

  Widget _buildShareScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SNS用画像')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: RepaintBoundary(
                  key: _previewKey,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: SharePhotoFrame(
                      bytes: _backgroundBytes,
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Image.asset(
                                key: const Key('shareBrandLogo'),
                                'assets/brand/setkeep_share_lockup.png',
                                width: 84,
                                height: 52,
                                fit: BoxFit.contain,
                              ),
                              const Spacer(),
                              Text(
                                '${widget.workout.date.year}.${widget.workout.date.month.toString().padLeft(2, '0')}.${widget.workout.date.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Flexible(
                                flex: 6,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.bottomLeft,
                                  child: SizedBox(
                                    width: 290,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _exerciseShareRows(
                                        widget.workout,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_backgroundBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                Localizations.localeOf(context).languageCode == 'en'
                    ? 'Drag the photo to adjust its position'
                    : '写真をドラッグして位置を調整できます',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('chooseSharePhotoButton'),
            onPressed: _choosePhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_backgroundBytes == null ? '背景写真を選ぶ' : '背景写真を変更'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('shareWorkoutImageButton'),
            onPressed: _sharing ? null : _saveImage,
            icon: _sharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
            label: Text(_sharing ? '画像を保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

List<Widget> _exerciseShareRows(WorkoutRecord workout) {
  return workout.exerciseGroups.values.map((sets) {
    final name = exerciseDisplayName(
      sets.first.exerciseName,
      exerciseId: sets.first.exerciseId,
    );
    final type = sets.first.recordType;
    final best = type == ExerciseRecordType.weightReps
        ? sets.reduce((a, b) => b.weight > a.weight ? b : a)
        : sets.first;
    final summary = switch (type) {
      ExerciseRecordType.weightReps ||
      ExerciseRecordType.assistedReps ||
      ExerciseRecordType.bodyweightReps =>
        '${best.displaySummary}  /  ${sets.length} セット',
      ExerciseRecordType.timed =>
        '${best.displaySummary}  /  ${sets.length} セット',
      ExerciseRecordType.cardio ||
      ExerciseRecordType.distance ||
      ExerciseRecordType.loadedDistance => best.displaySummary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 23,
            width: 290,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                exerciseDisplayName(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Text(
            summary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }).toList();
}

class WorkoutPage extends StatefulWidget {
  const WorkoutPage({
    super.key,
    this.history = const [],
    this.initialWorkout,
    this.isEditing = false,
    this.gymName,
    this.useDefaultPlace = false,
    this.initialPlace,
    this.resumeDraft = true,
    this.onSave,
  });

  final List<WorkoutRecord> history;
  final WorkoutRecord? initialWorkout;
  final bool isEditing;
  final String? gymName;
  final bool useDefaultPlace;
  final TrainingPlace? initialPlace;
  final bool resumeDraft;

  /// Host persists locally before the completion dialog opens.
  final Future<void> Function(WorkoutRecord)? onSave;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late DateTime _startedAt;
  late DateTime _workoutDate;
  String? _gymName;
  GymStore? _gymStore;
  String? _customPlaceId;
  bool _placeInitializing = false;
  Future<void>? _placeInitialization;
  Timer? _timer;
  Timer? _restTimer;
  Duration _elapsed = Duration.zero;
  int _restRemaining = 0;
  int _restRevision = 0;
  DateTime? _restEndsAt;
  String _restExerciseName = '';
  int _inputRevision = 0;
  late final _numericInput = WorkoutNumericInputController(() => _exercises);

  bool _allowPop = false;
  bool _leaveDialogOpen = false;
  bool _workoutTimerStopped = false;
  bool _restoringDraft = false;
  bool _exiting = false;
  bool _completing = false;
  WorkoutRecord? _savedRecord;
  WorkoutInterstitialSession? _completionAd;
  Future<WorkoutInterstitialSession?>? _completionAdLoading;
  late final _draftStore = WorkoutDraftStore(
    write: (value) async {
      final saved = await AndroidWorkoutDraft.write(value);
      _applyLockCompletions(saved);
    },
    remove: AndroidWorkoutDraft.clear,
  );
  String _sessionId = _newWorkoutIdentity();
  int _lockRevision = 0;
  Map<String, String>? _restTarget;

  void _applyLockCompletions(String? encoded) {
    if (encoded == null || !mounted || widget.isEditing || _exiting) return;
    final draft = jsonDecode(encoded) as Map<String, dynamic>;
    if (draft['sessionId'] != _sessionId) return;
    final revision = (draft['lockRevision'] as num?)?.toInt() ?? 0;
    if (revision <= _lockRevision) return;
    final completed = draft['lockCompleted'] as Map<String, dynamic>? ?? {};
    setState(() {
      for (final exercise in _exercises) {
        for (final set in exercise.sets) {
          if ((completed[set.setId] as num? ?? 0) > _lockRevision) {
            set.completed = true;
          }
        }
      }
      _lockRevision = revision;
    });
  }

  late final TextEditingController _noteController;
  late final List<WorkoutExercise> _exercises;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RestNotificationService.listen(() => unawaited(_syncRestState()));
    _gymName = widget.isEditing
        ? widget.initialWorkout?.gymName
        : widget.gymName;
    _customPlaceId = widget.isEditing
        ? widget.initialWorkout?.customPlaceId
        : null;
    final storeId = widget.isEditing ? widget.initialWorkout?.gymStoreId : null;
    if (storeId != null) {
      _gymStore = GymStore(id: storeId, chainName: '', name: _gymName ?? '店舗');
    }
    _startedAt = DateTime.now();
    _workoutDate = widget.isEditing
        ? widget.initialWorkout!.date
        : DateTime.now();
    _exercises = widget.initialWorkout == null
        ? []
        : _exercisesFrom(widget.initialWorkout!, completed: widget.isEditing);
    if (widget.isEditing) {
      final groups = groupRecordedSets(
        widget.initialWorkout!.sets,
        preserveStoredIds: true,
      ).values.toList();
      for (var i = 0; i < _exercises.length; i++) {
        for (var j = 0; j < _exercises[i].sets.length; j++) {
          _originalHistorySets[_exercises[i].sets[j]] = groups[i][j];
        }
      }
    }
    _noteController = TextEditingController(
      text: widget.isEditing ? widget.initialWorkout?.note ?? '' : '',
    );
    _noteController.addListener(_saveDraft);
    if (!widget.isEditing) {
      final place = widget.initialPlace;
      if (place != null) {
        _gymName = place.name;
        _gymStore = place.store;
        _customPlaceId = place.customPlaceId;
      }
      _placeInitializing = true;
      _placeInitialization = _initializePlaceAndDraft();
    }
    if (widget.isEditing) {
      _elapsed = Duration(seconds: widget.initialWorkout!.durationSeconds);
    } else if (WorkoutUiPreference.workoutTimerEnabled ||
        WorkoutUiPreference.workoutDurationEnabled) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_workoutTimerStopped) {
          setState(() => _elapsed = DateTime.now().difference(_startedAt));
        }
      });
    }
  }

  Future<void> _initializePlaceAndDraft() async {
    String? placeNotice = widget.initialPlace?.notice;
    try {
      if (widget.initialPlace == null &&
          (widget.useDefaultPlace || widget.gymName == null)) {
        final place = await TrainingPlacePreference.forNewWorkout();
        if (!mounted) return;
        placeNotice = place.notice;
        setState(() {
          _gymName = place.name;
          _gymStore = place.store;
          _customPlaceId = place.customPlaceId;
        });
      }
      if (widget.initialWorkout == null && widget.resumeDraft) {
        await _loadDraft();
      }
    } finally {
      _placeInitializing = false;
      if (mounted && placeNotice != null && !widget.isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(placeNotice!)));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _completionAd?.dispose();
    final loadingAd = _completionAdLoading;
    _completionAdLoading = null;
    if (loadingAd != null) {
      unawaited(
        loadingAd
            .then((session) => session?.dispose())
            .catchError((Object _) {}),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    RestNotificationService.listen(null);
    _timer?.cancel();
    _restTimer?.cancel();
    unawaited(RestNotificationService.cancel());
    _noteController.dispose();
    _numericInput.dispose();
    super.dispose();
  }

  void _prepareCompletionInterstitial() {
    if (widget.isEditing ||
        _completionAd != null ||
        _completionAdLoading != null) {
      return;
    }
    final ads = AdsScope.of(context);
    if (ads == null) return;
    _completionAdLoading =
        WorkoutInterstitialSession.prepareForWorkoutCompletion(
          config: ads.config,
          entitlement: ads.entitlement,
          platform: Theme.of(context).platform,
          backend: ads.interstitialBackend,
        );
  }

  Future<void> _resolveCompletionInterstitial() async {
    if (_completionAd != null) return;
    final loading = _completionAdLoading;
    _completionAdLoading = null;
    if (loading == null) return;
    try {
      _completionAd = await loading;
    } catch (_) {
      // Ads never affect workout storage, equipment confirmation or navigation.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncRestState());
  }

  Future<void> _syncRestState() async {
    if (widget.isEditing || _exiting) return;
    if (Platform.isAndroid) {
      _applyLockCompletions(await AndroidWorkoutDraft.read());
    }
    final requested = _restRevision;
    final native = await RestNotificationService.state();
    if (!mounted || _exiting || requested != _restRevision) return;
    if (!RestTimerPreference.enabled ||
        !WorkoutUiPreference.completionCheckEnabled) {
      _skipRest();
      return;
    }
    if (native != null) {
      if (Platform.isAndroid && native['target'] is Map) {
        final target = Map<String, String>.from(native['target'] as Map);
        _restTarget = target['sessionId'] == _sessionId ? target : null;
      }
      // Native may claim completion before this lifecycle/state callback. Show
      // the in-app message without cancelling its already-started sound.
      if (Platform.isAndroid &&
          _restEndsAt != null &&
          native['lastCompletionDeadline'] ==
              _restEndsAt!.millisecondsSinceEpoch &&
          (native['endsAtMilliseconds'] as num? ?? 0) == 0) {
        _finishRestTimer(notify: false);
        return;
      }
      _restRevision++;
      _restTimer?.cancel();
      final deadline = (native['endsAtMilliseconds'] as num?)?.toInt() ?? 0;
      _restEndsAt = deadline > 0
          ? DateTime.fromMillisecondsSinceEpoch(deadline)
          : null;
      _restExerciseName = native['exerciseName'] as String? ?? '';
      setState(
        () => _restRemaining = _restEndsAt == null
            ? (native['remainingSeconds'] as num?)?.toInt() ?? 0
            : remainingRestSeconds(_restEndsAt!, DateTime.now()),
      );
      if (_restEndsAt != null && _restRemaining > 0) _watchRestDeadline();
    }
    if (_restEndsAt != null) {
      final remaining = remainingRestSeconds(_restEndsAt!, DateTime.now());
      if (remaining <= 0) {
        _finishRestTimer(notify: false);
      } else {
        setState(() => _restRemaining = remaining);
      }
    }
  }

  String get _elapsedLabel {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration _stopWorkoutTimer({bool keepStopped = false}) {
    _restRevision++;
    if (!widget.isEditing && _timer != null) {
      _elapsed = DateTime.now().difference(_startedAt);
      _timer?.cancel();
      _timer = null;
    }
    if (keepStopped) _workoutTimerStopped = true;
    _restTimer?.cancel();
    _restTimer = null;
    _restEndsAt = null;
    _restRemaining = 0;
    unawaited(RestNotificationService.cancel());
    return _elapsed;
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      final sets = _exercises[exerciseIndex].sets;
      sets.add(WorkoutSet.nextFrom(sets.lastOrNull));
    });
    unawaited(_saveDraft());
  }

  bool _deletingWorkoutItem = false;
  final Map<WorkoutSet, RecordedSet> _originalHistorySets = {};

  Future<void> _persistWorkoutItems() async {
    if (!widget.isEditing) {
      await _saveDraft();
      return;
    }
    final original = widget.initialWorkout!;
    await widget.onSave?.call(
      WorkoutRecord.fromJson({
        ...original.toJson(),
        'sets': [
          for (final exercise in _exercises)
            for (final set in exercise.sets)
              _originalHistorySets[set] ??
                  RecordedSet(
                    exerciseName: exercise.name,
                    exerciseId: exercise.exerciseId,
                    equipment: exercise.equipment,
                    distanceUnit: exercise.distanceUnit,
                    bodyPart: exercise.bodyPart,
                    recordType: exercise.recordType,
                    weight: set.weight,
                    reps: set.reps,
                    durationSeconds: set.durationSeconds,
                    distanceKm: set.distanceKm,
                    speedKmh: set.speedKmh,
                    inclinePercent: set.inclinePercent,
                    resistanceLevel: set.resistanceLevel,
                    paceSecondsPerKm: set.paceSecondsPerKm,
                    completed: set.completed,
                  ),
        ].map((set) => set.toJson()).toList(),
      }),
    );
  }

  Future<void> _removeSet(int exerciseIndex, int setIndex) async {
    if (_deletingWorkoutItem) return;
    _deletingWorkoutItem = true;
    final exercise = _exercises[exerciseIndex];
    final removed = exercise.sets[setIndex];
    setState(() {
      exercise.sets.removeAt(setIndex);
      if (_exercises.every((item) => item.sets.isEmpty)) {
        _stopWorkoutTimer(keepStopped: true);
      }
    });
    try {
      await _persistWorkoutItems();
    } catch (_) {
      if (mounted) {
        setState(
          () => exercise.sets.insert(
            setIndex.clamp(0, exercise.sets.length),
            removed,
          ),
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('削除を保存できませんでした')));
      }
      return;
    } finally {
      _deletingWorkoutItem = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: workoutUndoDuration,
          persist: false,
          content: Text('${exercise.name}の${setIndex + 1}セット目を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              if (!mounted ||
                  _deletingWorkoutItem ||
                  !_exercises.contains(exercise)) {
                return;
              }
              _deletingWorkoutItem = true;
              setState(() {
                final restoreIndex = setIndex > exercise.sets.length
                    ? exercise.sets.length
                    : setIndex;
                exercise.sets.insert(restoreIndex, removed);
              });
              try {
                await _persistWorkoutItems();
              } catch (_) {
                if (!mounted) return;
                setState(() => exercise.sets.remove(removed));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('復元を保存できませんでした')));
              } finally {
                _deletingWorkoutItem = false;
              }
            },
          ),
        ),
      );
  }

  Future<void> _removeExercise(int exerciseIndex) async {
    if (_deletingWorkoutItem) return;
    _deletingWorkoutItem = true;
    final removed = _exercises[exerciseIndex];
    setState(() {
      _exercises.removeAt(exerciseIndex);
      if (_exercises.every((item) => item.sets.isEmpty)) {
        _stopWorkoutTimer(keepStopped: true);
      }
    });
    try {
      await _persistWorkoutItems();
    } catch (_) {
      if (mounted) {
        setState(
          () => _exercises.insert(
            exerciseIndex.clamp(0, _exercises.length),
            removed,
          ),
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('削除を保存できませんでした')));
      }
      return;
    } finally {
      _deletingWorkoutItem = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: workoutUndoDuration,
          persist: false,
          content: Text('${removed.name}を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              if (!mounted ||
                  _deletingWorkoutItem ||
                  _exercises.contains(removed)) {
                return;
              }
              _deletingWorkoutItem = true;
              setState(() {
                final restoreIndex = exerciseIndex > _exercises.length
                    ? _exercises.length
                    : exerciseIndex;
                _exercises.insert(restoreIndex, removed);
              });
              try {
                await _persistWorkoutItems();
              } catch (_) {
                if (!mounted) return;
                setState(() => _exercises.remove(removed));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('復元を保存できませんでした')));
              } finally {
                _deletingWorkoutItem = false;
              }
            },
          ),
        ),
      );
  }

  Future<void> _toggleSet(int exerciseIndex, int setIndex) async {
    final exercise = _exercises[exerciseIndex];
    final set = exercise.sets[setIndex];
    setState(() => set.completed = !set.completed);
    if (Platform.isAndroid) {
      await _saveDraft();
    } else {
      unawaited(_saveDraft());
    }
    if (!mounted ||
        _exiting ||
        !_exercises.contains(exercise) ||
        !exercise.sets.contains(set)) {
      return;
    }
    setIndex = exercise.sets.indexOf(set);
    if (set.completed) HapticFeedback.mediumImpact();
    if (set.completed &&
        !widget.isEditing &&
        WorkoutUiPreference.completionCheckEnabled &&
        RestTimerPreference.enabled) {
      if (Platform.isAndroid) {
        await _advanceAndroidRest(exercise);
      } else if (setIndex == exercise.sets.length - 1) {
        _skipRest();
      } else {
        _restExerciseName = exerciseDisplayName(
          exercise.name,
          exerciseId: exercise.exerciseId,
        );
        _restTarget = {
          'sessionId': _sessionId,
          'exerciseInstanceId': exercise.instanceId,
          'previousSetId': set.setId,
          'targetSetId': exercise.sets[setIndex + 1].setId,
        };
        _startRestTimer();
      }
    }
  }

  Future<void> _advanceAndroidRest(WorkoutExercise exercise) async {
    final revision = _restRevision;
    final target = await AndroidWorkoutDraft.nextTarget(
      _sessionId,
      exercise.instanceId,
    );
    if (!mounted || _exiting || revision != _restRevision) return;
    if (target == null) {
      _restTarget = null;
      _skipRest();
    } else {
      _restTarget = target;
      _restExerciseName = target['exerciseName'] ?? exercise.name;
      _startRestTimer();
    }
  }

  void _applyPreviousSets(int exerciseIndex, List<RecordedSet> previousSets) {
    if (previousSets.isEmpty) return;
    setState(() {
      _inputRevision++;
      final sets = _exercises[exerciseIndex].sets;
      sets
        ..clear()
        ..addAll(
          previousSets.map(
            (set) => WorkoutSet(
              weight: set.weight,
              reps: set.reps,
              durationSeconds: set.durationSeconds,
              distanceKm: set.distanceKm,
              speedKmh: set.speedKmh,
              inclinePercent: set.inclinePercent,
              resistanceLevel: set.resistanceLevel,
              paceSecondsPerKm: set.paceSecondsPerKm,
            ),
          ),
        );
    });
    unawaited(_saveDraft());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_exercises[exerciseIndex].name}に前回の記録を反映しました')),
    );
  }

  Future<void> _setAllSetsCompleted(int exerciseIndex, bool completed) async {
    final exercise = _exercises[exerciseIndex];
    setState(() {
      for (final set in _exercises[exerciseIndex].sets) {
        set.completed = completed;
      }
    });
    if (completed) HapticFeedback.mediumImpact();
    if (Platform.isAndroid) {
      await _saveDraft();
    } else {
      unawaited(_saveDraft());
    }
    if (!mounted || _exiting) return;
    if (completed &&
        !widget.isEditing &&
        WorkoutUiPreference.completionCheckEnabled &&
        RestTimerPreference.enabled) {
      if (Platform.isAndroid) {
        await _advanceAndroidRest(exercise);
      } else {
        _skipRest();
      }
    }
  }

  Future<void> _startRestTimer([int? seconds]) async {
    final revision = ++_restRevision;
    if (Platform.isAndroid && !widget.isEditing && _exercises.isNotEmpty) {
      await _saveDraft();
      if (!mounted ||
          _exiting ||
          _exercises.isEmpty ||
          revision != _restRevision) {
        return;
      }
      final current = _restTarget?['exerciseInstanceId'];
      final exercise = _exercises.firstWhere(
        (e) => e.instanceId == current,
        orElse: () => _exercises.first,
      );
      final target = await AndroidWorkoutDraft.nextTarget(
        _sessionId,
        exercise.instanceId,
      );
      if (!mounted || _exiting || revision != _restRevision) return;
      _restTarget = target;
      if (target != null) {
        _restExerciseName = target['exerciseName'] ?? exercise.name;
      }
    }
    _restTimer?.cancel();
    final duration = seconds ?? RestTimerPreference.seconds;
    _restEndsAt = DateTime.now().add(Duration(seconds: duration));
    setState(() => _restRemaining = duration);
    unawaited(
      RestNotificationService.schedule(
        duration,
        endsAt: _restEndsAt,
        exerciseName: _restExerciseName,
        target: _restTarget,
        restSeconds: RestTimerPreference.seconds,
      ),
    );
    _watchRestDeadline();
  }

  void _watchRestDeadline() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _restEndsAt == null) return;
      final remaining = remainingRestSeconds(_restEndsAt!, DateTime.now());
      if (remaining <= 0) return _finishRestTimer();
      setState(() => _restRemaining = remaining);
    });
  }

  void _finishRestTimer({bool notify = true}) {
    if (_restEndsAt == null) return;
    final deadline = _restEndsAt!;
    final revision = ++_restRevision;
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _restTimer?.cancel();
    _restTimer = null;
    _restEndsAt = null;
    if (Platform.isAndroid) {
      // Never cancel on natural expiry: cancel also stops native playback and
      // removes the Alarm. Duplicate due requests are ignored by the native claim.
      unawaited(RestNotificationService.completeIfDue(deadline));
    } else if (foreground) {
      unawaited(
        RestNotificationService.cancel().then((_) async {
          if (mounted && notify && revision == _restRevision) {
            await RestNotificationService.playCompletionFeedback();
          }
        }),
      );
    }
    if (mounted) {
      setState(() => _restRemaining = 0);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            key: Key('restTimerFinishedMessage'),
            content: Text('休憩終了。次のセットへ！'),
          ),
        );
    }
  }

  void _pauseRest() {
    _restRevision++;
    if (_restEndsAt == null) return;
    final remaining = remainingRestSeconds(_restEndsAt!, DateTime.now());
    _restTimer?.cancel();
    _restTimer = null;
    _restEndsAt = null;
    if (Platform.isAndroid) {
      unawaited(RestNotificationService.pause().then((_) => _syncRestState()));
    } else {
      unawaited(RestNotificationService.cancel(remainingSeconds: remaining));
    }
    setState(() => _restRemaining = remaining);
  }

  Future<void> _resumeRest() async {
    if (Platform.isAndroid && _restRemaining > 0) {
      final native = await RestNotificationService.state();
      if (native?['phase'] == 'running') {
        await _syncRestState();
        return;
      }
      if (native?['phase'] == 'paused') {
        await RestNotificationService.resume();
        await _syncRestState();
        return;
      }
    }
    await _startRestTimer(
      _restRemaining > 0 ? _restRemaining : RestTimerPreference.seconds,
    );
  }

  void _skipRest() {
    _restRevision++;
    _restTimer?.cancel();
    _restTimer = null;
    _restEndsAt = null;
    unawaited(RestNotificationService.cancel());
    setState(() => _restRemaining = 0);
  }

  String get _configuredRestLabel =>
      '${(RestTimerPreference.seconds ~/ 60).toString().padLeft(2, '0')}:${(RestTimerPreference.seconds % 60).toString().padLeft(2, '0')}';

  String get _restLabel {
    final minutes = (_restRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_restRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _addExercise() async {
    await _placeInitialization;
    if (!mounted) return;
    final existingIdentities = _exercises.map((item) => item.identity).toSet();
    final menus = await WorkoutTemplatePreference.load();
    if (!mounted) return;
    final selected = await showModalBottomSheet<List<ExerciseSelection>>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExercisePickerViewport(
        child: ExercisePickerSheet(
          existingIdentities: existingIdentities,
          gymStoreId: _gymStore?.id,
          customPlaceId: _customPlaceId,
          menus: menus,
        ),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    _applyExerciseSelection(selected);
  }

  void _applyExerciseSelection(List<ExerciseSelection> selected) {
    setState(() {
      final names = _exercises.map((item) => item.identity).toSet();
      for (final item in selected) {
        if (!names.add(item.template.identity)) continue;
        if (item.savedSets == null) {
          _exercises.add(_exerciseFromTemplate(item.template));
        } else {
          _exercises.addAll(
            _exercisesFrom(
              WorkoutRecord(date: _workoutDate, sets: item.savedSets!),
              completed: false,
            ),
          );
        }
      }
    });
    unawaited(_saveDraft());
  }

  Future<void> _loadDraft() async {
    final encoded = await AndroidWorkoutDraft.read();
    if (encoded == null || !mounted || _draftStore.isClosed || _exiting) return;
    try {
      final draft = jsonDecode(encoded) as Map<String, dynamic>;
      _sessionId = draft['sessionId'] as String? ?? _sessionId;
      _lockRevision = (draft['lockRevision'] as num?)?.toInt() ?? 0;
      final exercises = (draft['exercises'] as List<dynamic>)
          .map((item) => _exerciseFromDraft(item as Map<String, dynamic>))
          .toList();
      final timerStopped = draft['timerStopped'] as bool? ?? false;
      if (exercises.isEmpty &&
          (draft['gymName'] is! String ||
              (draft['gymName'] as String).trim().isEmpty)) {
        await AndroidWorkoutDraft.clear();
        return;
      }
      _restoringDraft = true;
      setState(() {
        _inputRevision++;
        if (timerStopped) {
          _timer?.cancel();
          _timer = null;
          _workoutTimerStopped = true;
        }
        final savedElapsedSeconds = (draft['elapsedSeconds'] as num?)?.toInt();
        if (savedElapsedSeconds != null) {
          _elapsed = Duration(seconds: savedElapsedSeconds);
          _startedAt = DateTime.now().subtract(_elapsed);
        } else {
          final savedStartedAt = draft['startedAt'] as String?;
          if (savedStartedAt != null) {
            _startedAt = DateTime.tryParse(savedStartedAt) ?? _startedAt;
            _elapsed = DateTime.now().difference(_startedAt);
          }
        }
        _exercises
          ..clear()
          ..addAll(exercises);
        if (draft.containsKey('gymName')) {
          final gym = draft['gymName'];
          if (gym == null || gym is String) _gymName = gym as String?;
        }
        // Name-only legacy drafts stay name-only. Drafts predating location
        // storage keep the caller's default name and store ID together.
        if (draft.containsKey('gymName') || draft.containsKey('gymStoreId')) {
          _customPlaceId = draft['customPlaceId'] as String?;
          final storeId = draft['gymStoreId'] as String?;
          _gymStore = storeId == null
              ? null
              : GymStore(id: storeId, chainName: '', name: _gymName ?? '店舗');
        }
        _noteController.text = draft['note'] as String? ?? '';
        final savedDate = draft['date'] as String?;
        if (savedDate != null) _workoutDate = DateTime.parse(savedDate);
      });
      if (timerStopped) {
        _stopWorkoutTimer(keepStopped: true);
      }
      await _syncRestState();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('入力途中のトレーニングを再開しました')));
      }
    } catch (_) {
      await AndroidWorkoutDraft.clear();
    } finally {
      _restoringDraft = false;
    }
  }

  Future<void> _selectWorkoutGym() async {
    await _placeInitialization;
    if (!mounted) return;
    GymStore? store;
    String? customId;
    final selected = await showGymPicker(
      context,
      _gymName,
      currentStoreId: _gymStore?.id,
      currentCustomPlaceId: _customPlaceId,
      onStoreSelected: (value) => store = value,
      onPlaceSelected: (value) => customId = value.customPlaceId,
    );
    if (!mounted || selected == null) return;
    if (store?.id == _gymStore?.id &&
        customId == _customPlaceId &&
        selected == _gymName) {
      return;
    }
    setState(() {
      _gymName = selected;
      _gymStore = store;
      _customPlaceId = customId;
    });
    await _saveDraft();
  }

  Future<void> _openGymEquipment() async {
    final store = _gymStore;
    if (store == null && _customPlaceId == null) return;
    Future<void> add(Set<String> ids) async {
      if (!mounted) return;
      _applyExerciseSelection(
        exerciseTemplates
            .where((e) => ids.contains(e.exerciseId))
            .map((e) => ExerciseSelection(e))
            .toList(),
      );
      await _saveDraft();
    }

    final existing = _exercises
        .map((e) => e.exerciseId)
        .whereType<String>()
        .map(ExerciseFormCatalog.canonicalId)
        .toSet();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => store != null
            ? GymStoreEquipmentPage(
                store: store,
                existingIds: existing,
                onAdd: add,
              )
            : PrivatePlaceEquipmentPage(
                placeId: _customPlaceId!,
                name: _gymName ?? '利用場所',
                existingIds: existing,
                onAdd: add,
              ),
      ),
    );
  }

  Future<void> _saveDraft() async {
    if (widget.isEditing ||
        _placeInitializing ||
        _restoringDraft ||
        _draftStore.isClosed) {
      return;
    }
    final encodedDraft = jsonEncode({
      if (Platform.isAndroid) 'sessionId': _sessionId,
      if (Platform.isAndroid) 'lockRevision': _lockRevision,
      'startedAt': _startedAt.toIso8601String(),
      'elapsedSeconds': _elapsed.inSeconds,
      'timerStopped': _workoutTimerStopped,
      'date': _workoutDate.toIso8601String(),
      'note': _noteController.text,
      'gymName': _gymName,
      'gymStoreId': _gymStore?.id,
      if (_customPlaceId != null) 'customPlaceId': _customPlaceId,
      'exercises': _exercises
          .map(
            (exercise) => {
              if (Platform.isAndroid) 'instanceId': exercise.instanceId,
              'name': exercise.name,
              if (exercise.exerciseId != null)
                'exerciseId': exercise.exerciseId,
              'distanceUnit': exercise.distanceUnit,
              'bodyPart': exercise.bodyPart,
              'equipment': exercise.equipment,
              'recordType': exercise.recordType.name,
              'sets': exercise.sets
                  .map(
                    (set) => {
                      if (Platform.isAndroid) 'setId': set.setId,
                      'weight': set.weight,
                      'reps': set.reps,
                      'durationSeconds': set.durationSeconds,
                      'distanceKm': set.distanceKm,
                      'speedKmh': set.speedKmh,
                      'inclinePercent': set.inclinePercent,
                      'resistanceLevel': set.resistanceLevel,
                      'paceSecondsPerKm': set.paceSecondsPerKm,
                      'completed': set.completed,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    });
    await _draftStore.save(encodedDraft);
  }

  Future<void> _clearDraft() => _draftStore.clear();

  WorkoutExercise _exerciseFromDraft(Map<String, dynamic> json) {
    return WorkoutExercise(
      instanceId: json['instanceId'] as String?,
      name: json['name'] as String,
      exerciseId: json['exerciseId'] as String?,
      distanceUnit: json['distanceUnit'] as String? ?? 'km',
      bodyPart: json['bodyPart'] as String,
      equipment: json['equipment'] as String,
      recordType: json['recordType'] == null
          ? recordTypeForExerciseName(
              json['name'] as String,
              bodyPart: json['bodyPart'] as String,
              equipment: json['equipment'] as String,
            )
          : ExerciseRecordType.fromName(json['recordType'] as String?),
      sets: (json['sets'] as List<dynamic>).map((item) {
        final setJson = item as Map<String, dynamic>;
        return WorkoutSet(
          setId: setJson['setId'] as String?,
          weight: (setJson['weight'] as num?)?.toDouble() ?? 0,
          reps: (setJson['reps'] as num?)?.toInt() ?? 0,
          durationSeconds: (setJson['durationSeconds'] as num?)?.toInt() ?? 0,
          distanceKm: (setJson['distanceKm'] as num?)?.toDouble() ?? 0,
          speedKmh: (setJson['speedKmh'] as num?)?.toDouble() ?? 0,
          inclinePercent: (setJson['inclinePercent'] as num?)?.toDouble() ?? 0,
          resistanceLevel:
              (setJson['resistanceLevel'] as num?)?.toDouble() ?? 0,
          paceSecondsPerKm: (setJson['paceSecondsPerKm'] as num?)?.toInt() ?? 0,
        )..completed = setJson['completed'] as bool? ?? false;
      }).toList(),
    );
  }

  Future<void> _selectWorkoutDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _workoutDate.isAfter(now) ? now : _workoutDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: 'トレーニング日',
      cancelText: 'キャンセル',
      confirmText: '決定',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _workoutDate = preserveWorkoutTime(_workoutDate, selected);
    });
    unawaited(_saveDraft());
  }

  Future<void> _confirmLeave() async {
    if (_completing || _savedRecord != null || _leaveDialogOpen) return;
    _leaveDialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.isEditing ? '修正を中止しますか？' : 'トレーニングを中断しますか？'),
        content: Text(
          widget.isEditing ? '変更した内容は保存されません。' : '入力内容は自動保存され、次回ここから再開できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('入力を続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(widget.isEditing ? '戻る' : '中断する'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (leave == true) await _exitWorkout();
  }

  Future<void> _exitWorkout([WorkoutRecord? workout]) async {
    if (!mounted || _exiting) return;
    _exiting = true;
    try {
      if (!widget.isEditing) {
        _stopWorkoutTimer();
        if (workout == null) await _saveDraft();
      }
    } catch (error) {
      _exiting = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('入力内容を保存できませんでした。もう一度お試しください。')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(workout);
    });
  }

  Future<void> _deleteWorkoutDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('記録をすべて削除しますか？'),
        content: const Text('入力中の種目・セット・メモを削除します。この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirmDeleteWorkoutDraftButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _stopWorkoutTimer(keepStopped: true);
    await _clearDraft();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<WorkoutRecord>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_numericInput.isActive) {
            FocusManager.instance.primaryFocus?.unfocus();
          } else {
            unawaited(_confirmLeave());
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          centerTitle: true,
          leading: BackButton(onPressed: _confirmLeave),
          title: Text(
            widget.isEditing ? '記録を修正' : 'トレーニング',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          actions: [
            if (!widget.isEditing)
              IconButton(
                key: const Key('deleteWorkoutDraftButton'),
                tooltip: '記録を全削除',
                onPressed: _completing || _savedRecord != null
                    ? null
                    : _deleteWorkoutDraft,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            OutlinedButton(
              key: const Key('completeWorkoutButton'),
              onPressed: _completing ? null : _completeWorkout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF426B83),
                side: const BorderSide(color: Color(0xFF426B83), width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                widget.isEditing ? '保存' : '完了',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: _numericInput.keypad,
        body: _numericInput.wrap(
          AbsorbPointer(
            absorbing: _completing || _savedRecord != null,
            child: Form(
              key: _formKey,
              child: ListView(
                key: const Key('workoutScrollView'),
                padding: EdgeInsets.fromLTRB(
                  16 + MediaQuery.paddingOf(context).left,
                  8,
                  16 + MediaQuery.paddingOf(context).right,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Column(
                    key: const Key('workoutInfoCard'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label: 'トレーニング日 ${workoutDateLabel(_workoutDate)}',
                        button: true,
                        child: InkWell(
                          key: const Key('workoutDateButton'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: _selectWorkoutDate,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '${_workoutDate.month}.${_workoutDate.day}（${const ['月', '火', '水', '木', '金', '土', '日'][_workoutDate.weekday - 1]}）',
                                          key: const Key('workoutDateValue'),
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 36,
                                            height: 1.15,
                                            fontWeight: FontWeight.w900,
                                            color: colors.onSurface,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_workoutDate.year}年',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.edit_calendar_outlined,
                                  color: colors.onSurface,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('workoutGymButton'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: colors.onSurfaceVariant,
                        ),
                        title: Text(
                          _gymName ?? '未選択',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _selectWorkoutGym,
                      ),
                      if (_gymStore != null || _customPlaceId != null)
                        OutlinedButton.icon(
                          key: const Key('workoutGymEquipmentButton'),
                          onPressed: _openGymEquipment,
                          icon: const Icon(Icons.fitness_center),
                          label: Text(
                            _gymStore != null
                                ? 'この店舗の設備から種目を追加'
                                : 'この場所の設備から種目を追加',
                          ),
                        ),
                      if (WorkoutUiPreference.workoutTimerEnabled ||
                          (widget.isEditing &&
                              WorkoutUiPreference.workoutDurationEnabled))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.isEditing
                                    ? widget.initialWorkout!.durationLabel
                                    : _elapsedLabel,
                                key: const Key('workoutElapsedLabel'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!widget.isEditing &&
                      WorkoutUiPreference.completionCheckEnabled &&
                      RestTimerPreference.enabled) ...[
                    Container(
                      key: const Key('restTimerBanner'),
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.fromLTRB(14, 4, 10, 12),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).cardTheme.color ??
                            colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '休憩タイマー',
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (Platform.isAndroid &&
                                      (_restEndsAt != null ||
                                          _restRemaining > 0) &&
                                      await RestNotificationService.extend()) {
                                    await _syncRestState();
                                    return;
                                  }
                                  if (_restEndsAt != null) {
                                    await _startRestTimer(_restRemaining + 30);
                                  } else {
                                    setState(
                                      () => _restRemaining =
                                          (_restRemaining > 0
                                              ? _restRemaining
                                              : RestTimerPreference.seconds) +
                                          30,
                                    );
                                  }
                                },
                                child: const Text('+30秒'),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: colors.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _restRemaining > 0
                                      ? _restLabel
                                      : _configuredRestLabel,
                                  key: const Key('restRemainingLabel'),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: Key(
                                  _restEndsAt != null
                                      ? 'stopRestTimerButton'
                                      : 'startRestTimerButton',
                                ),
                                onPressed: _restEndsAt != null
                                    ? _pauseRest
                                    : _resumeRest,
                                style: IconButton.styleFrom(
                                  backgroundColor: colors.secondaryContainer,
                                  foregroundColor: colors.onSecondaryContainer,
                                  minimumSize: const Size(48, 48),
                                ),
                                tooltip: _restEndsAt != null ? '一時停止' : '開始・再開',
                                icon: Icon(
                                  _restEndsAt != null
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    key: const Key('workoutExercisesHeading'),
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 22,
                          color: colors.secondary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'トレーニング種目',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${_exercises.length}種目',
                          key: const Key('workoutExerciseCount'),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_exercises.isEmpty) ...[
                    Container(
                      key: const Key('emptyWorkoutExercises'),
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE0E4DE)),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.fitness_center_rounded,
                            size: 34,
                            color: Color(0xFF777F78),
                          ),
                          SizedBox(height: 12),
                          Text(
                            '種目はまだありません',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '下の「種目を追加」から選んでください',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF777F78)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Keep numeric fields mounted across cards for keyboard traversal.
                  Column(
                    children: List.generate(
                      _exercises.length,
                      (exerciseIndex) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ExerciseInputCard(
                          key: ValueKey((
                            _exercises[exerciseIndex].sets,
                            _inputRevision,
                          )),
                          numericNodes: _numericInput.nodesFor,
                          nextNumeric: _numericInput.nextNumeric,
                          exerciseIndex: exerciseIndex,
                          exercise: _exercises[exerciseIndex],
                          history: widget.history,
                          onAddSet: () => _addSet(exerciseIndex),
                          onRemoveSet: (setIndex) =>
                              _removeSet(exerciseIndex, setIndex),
                          onRemove: () => _removeExercise(exerciseIndex),
                          onToggleSet: (setIndex) =>
                              _toggleSet(exerciseIndex, setIndex),
                          onApplyPrevious: (sets) =>
                              _applyPreviousSets(exerciseIndex, sets),
                          onSetAllCompleted: (completed) =>
                              _setAllSetsCompleted(exerciseIndex, completed),
                          onValuesChanged: _saveDraft,
                          onRecordTypeChanged: () {
                            setState(() {});
                            unawaited(_saveDraft());
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      key: const Key('addExerciseButton'),
                      onPressed: _addExercise,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF101820),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        '種目を追加',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'トレーニングメモ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteController,
                          maxLines: 3,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            hintText: 'フォームや体調などをメモ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeWorkout() async {
    if (_deletingWorkoutItem) return;
    if (_completing || _exiting) return;
    if (Platform.isAndroid && !widget.isEditing) {
      setState(() => _completing = true);
      try {
        _applyLockCompletions(await AndroidWorkoutDraft.freezeActions());
      } catch (_) {
        if (mounted) {
          setState(() => _completing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('記録を確認できませんでした。もう一度お試しください。')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _completing = false);
    }
    _formKey.currentState?.save();
    final completedSets = <RecordedSet>[
      for (final exercise in _exercises)
        for (final set in exercise.sets)
          if (!WorkoutUiPreference.completionCheckEnabled ||
              !exercise.recordType.usesSets ||
              set.completed)
            RecordedSet(
              exerciseName: exercise.name,
              exerciseId: exercise.exerciseId,
              equipment: exercise.equipment,
              distanceUnit: exercise.distanceUnit,
              bodyPart: exercise.bodyPart,
              recordType: exercise.recordType,
              weight: set.weight,
              reps: set.reps,
              durationSeconds: set.durationSeconds,
              distanceKm: set.distanceKm,
              speedKmh: set.speedKmh,
              inclinePercent: set.inclinePercent,
              resistanceLevel: set.resistanceLevel,
              paceSecondsPerKm: set.paceSecondsPerKm,
              completed: true,
            ),
    ];
    if (completedSets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('完了したセットを1つ以上チェックしてください')));
      return;
    }

    final invalidSet = completedSets
        .where((set) => !set.hasRequiredValues)
        .firstOrNull;
    if (invalidSet != null) {
      final message = invalidSet.isTreadmill
          ? '時間または距離を入力してください'
          : '記録項目に1以上の数字を入力してください';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
      );
      return;
    }
    _prepareCompletionInterstitial();
    FocusScope.of(context).unfocus();
    late final Duration finalElapsed;
    setState(() {
      finalElapsed = _stopWorkoutTimer(keepStopped: true);
    });
    final personalBests = _personalBestExercises(completedSets);
    final completedSetCount = completedSets
        .where((set) => set.recordType.usesSets)
        .length;
    final activityCount = completedSets.length - completedSetCount;
    final completionCountLabel = [
      if (completedSetCount > 0) '$completedSetCountセット',
      if (activityCount > 0) '有酸素・移動 $activityCount件',
    ].join('・');
    final record =
        _savedRecord ??
        WorkoutRecord(
          date: _workoutDate,
          sets: completedSets,
          durationSeconds: widget.isEditing
              ? widget.initialWorkout!.durationSeconds
              : WorkoutUiPreference.workoutDurationEnabled
              ? finalElapsed.inSeconds
              : 0,
          gymName: _gymName,
          gymStoreId: _gymStore?.id,
          customPlaceId: _customPlaceId,
          note: _noteController.text.trim(),
          trainerWorkoutId: widget.isEditing
              ? widget.initialWorkout!.trainerWorkoutId
              : null,
          trainerOwnerUserId: widget.isEditing
              ? widget.initialWorkout!.trainerOwnerUserId
              : null,
        );
    setState(() => _completing = true);
    try {
      // Retry draft cleanup without inserting the already persisted record twice.
      if (_savedRecord == null) {
        await widget.onSave?.call(record);
        _savedRecord = record;
      }
      if (!widget.isEditing) await _clearDraft();
    } catch (_) {
      if (mounted) {
        setState(() => _completing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できませんでした。もう一度「完了」を押してください。')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (!widget.isEditing) {
      await confirmWorkoutEquipment(
        context,
        equipmentWorkoutFromRecord(record),
      );
      unawaited(
        syncSavedTrainingEquipment().catchError((Object error) {
          debugPrint('Equipment confirmation sync deferred: $error');
        }),
      );
    }
    if (!mounted) return;
    await _resolveCompletionInterstitial();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(widget.isEditing ? '修正を保存' : 'トレーニング完了'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$completionCountLabelを${widget.isEditing ? '保存' : '記録'}しました。',
              ),
              if (!widget.isEditing && personalBests.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreenSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '自己ベスト更新\n${personalBests.join('・')}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!widget.isEditing)
              TextButton(
                key: const Key('completeWithoutSharingButton'),
                onPressed: () async {
                  if (!dialogContext.mounted || !mounted) return;
                  Navigator.of(dialogContext).pop();
                  await _completionAd?.tryShow();
                  await _exitWorkout(record);
                },
                child: const Text('ホームへ戻る'),
              ),
            FilledButton(
              key: const Key('completeAndPreviewShareButton'),
              onPressed: () async {
                if (!dialogContext.mounted || !mounted) return;
                Navigator.of(dialogContext).pop();
                if (widget.isEditing) {
                  _exitWorkout(record);
                  return;
                }
                // Saving and draft cleanup have finished. Replace the ended
                // workout so every share-page exit returns to its home caller.
                final completionAd = _completionAd;
                _completionAd = null;
                _exiting = true;
                Navigator.of(context).pushReplacement<void, WorkoutRecord>(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkoutSharePage(
                      workout: record,
                      completionFlow: true,
                      completionAd: completionAd,
                    ),
                  ),
                  result: record,
                );
              },
              child: Text(widget.isEditing ? '閉じる' : '共有画像を確認'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _personalBestExercises(List<RecordedSet> completedSets) {
    final names = completedSets
        .where((set) => set.recordType == ExerciseRecordType.weightReps)
        .map((set) => set.identity)
        .toSet();
    return names
        .where((name) {
          final currentBest = completedSets
              .where((set) => set.identity == name)
              .fold<double>(
                0,
                (best, set) => set.weight > best ? set.weight : best,
              );
          final previousBest = widget.history
              .expand((workout) => workout.sets)
              .where((set) => set.identity == name)
              .fold<double>(
                0,
                (best, set) => set.weight > best ? set.weight : best,
              );
          return currentBest > previousBest;
        })
        .map((key) {
          final set = completedSets.firstWhere((set) => set.identity == key);
          return exerciseDisplayName(
            set.exerciseName,
            exerciseId: set.exerciseId,
          );
        })
        .toList();
  }

  WorkoutExercise _exerciseFromTemplate(ExerciseTemplate template) {
    final previousSets = latestSetsForExercise(
      widget.history,
      template.name,
      exerciseId: template.exerciseId,
    );
    if (previousSets.isNotEmpty) {
      return WorkoutExercise(
        name: template.name,
        exerciseId: template.exerciseId,
        distanceUnit: template.distanceUnit,
        bodyPart: template.bodyPart,
        equipment: template.equipment,
        recordType: template.recordType,
        sets: previousSets.map(_workoutSetFromRecorded).toList(),
      );
    }
    return WorkoutExercise(
      name: template.name,
      exerciseId: template.exerciseId,
      distanceUnit: template.distanceUnit,
      bodyPart: template.bodyPart,
      equipment: template.equipment,
      recordType: template.recordType,
      sets: List.generate(
        1,
        (_) => WorkoutSet(
          weight: template.recordType.hasWeightInput ? template.startWeight : 0,
          reps: template.recordType == ExerciseRecordType.timed
              ? 0
              : template.startReps,
          durationSeconds: template.recordType == ExerciseRecordType.timed
              ? template.startReps
              : template.recordType == ExerciseRecordType.cardio ||
                    template.recordType == ExerciseRecordType.distance
              ? template.startReps * 60
              : 0,
        ),
      ),
    );
  }

  static List<WorkoutExercise> _exercisesFrom(
    WorkoutRecord workout, {
    required bool completed,
  }) => groupRecordedSets(workout.sets, preserveStoredIds: true).values.map((
    recordedSets,
  ) {
    final first = recordedSets.first;
    final legacy = _legacyExerciseTemplates.where(
      (item) => item.name == first.exerciseName,
    );
    return WorkoutExercise(
      name: first.exerciseName,
      exerciseId: first.exerciseId,
      distanceUnit: first.distanceUnit,
      bodyPart: first.bodyPart,
      equipment: first.equipment.isNotEmpty
          ? first.equipment
          : first.exerciseId != null
          ? ExerciseFormCatalog.byId[first.exerciseId]?.equipmentLabel ?? 'カスタム'
          : legacy.isNotEmpty
          ? legacy.first.equipment
          : 'フリーウェイト',
      recordType: first.recordType,
      sets: recordedSets
          .map((set) => _workoutSetFromRecorded(set)..completed = completed)
          .toList(),
    );
  }).toList();

  static WorkoutSet _workoutSetFromRecorded(RecordedSet set) => WorkoutSet(
    weight: set.weight,
    reps: set.reps,
    durationSeconds: set.durationSeconds,
    distanceKm: set.distanceKm,
    speedKmh: set.speedKmh,
    inclinePercent: set.inclinePercent,
    resistanceLevel: set.resistanceLevel,
    paceSecondsPerKm: set.paceSecondsPerKm,
  );
}

DateTime preserveWorkoutTime(DateTime original, DateTime calendarDay) =>
    DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
      original.hour,
      original.minute,
      original.second,
      original.millisecond,
      original.microsecond,
    );

String workoutDateLabel(DateTime date) {
  final now = DateTime.now();
  final isToday =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final formatted = '${date.year}年${date.month}月${date.day}日';
  return isToday ? '今日・$formatted' : formatted;
}

class SavedWorkoutTemplate {
  const SavedWorkoutTemplate({required this.name, required this.sets});

  final String name;
  final List<RecordedSet> sets;

  Map<String, List<RecordedSet>> get exerciseGroups => groupRecordedSets(sets);
  List<String> get exerciseNames => exerciseGroups.values
      .map(
        (group) => exerciseDisplayName(
          group.first.exerciseName,
          exerciseId: group.first.exerciseId,
        ),
      )
      .toList(growable: false);

  WorkoutRecord toWorkoutRecord() =>
      WorkoutRecord(date: DateTime.now(), sets: sets);

  factory SavedWorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      SavedWorkoutTemplate(
        name: json['name'] as String,
        sets: (json['sets'] as List<dynamic>)
            .map((item) => RecordedSet.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  static SavedWorkoutTemplate? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final template = SavedWorkoutTemplate.fromJson(source);
      if (template.name.trim().isEmpty || template.sets.isEmpty) return null;
      return template;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

class WorkoutTemplatePreference {
  WorkoutTemplatePreference._();

  static const _storageKey = 'workout_templates';

  static Future<List<SavedWorkoutTemplate>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) return [];
    try {
      return decodeWorkoutTemplates(jsonDecode(encoded));
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedWorkoutTemplate> templates) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(templates.map((item) => item.toJson()).toList()),
    );
  }
}

class SetkeepBackup {
  const SetkeepBackup({
    required this.workouts,
    this.workoutTemplates = const [],
    this.bodyWeights = const [],
    this.customExercises = const [],
    this.customGyms = const [],
    this.selectedGym,
    this.restTimerEnabled,
    this.restTimerSeconds,
    this.completionCheckEnabled,
    this.workoutTimerEnabled,
    this.workoutDurationEnabled,
  });

  final List<WorkoutRecord> workouts;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final List<BodyWeightEntry> bodyWeights;
  final List<ExerciseTemplate> customExercises;
  final List<String> customGyms;
  final String? selectedGym;
  final bool? restTimerEnabled;
  final int? restTimerSeconds;
  final bool? completionCheckEnabled;
  final bool? workoutTimerEnabled;
  final bool? workoutDurationEnabled;

  factory SetkeepBackup.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    final supportedApp =
        json['app'] == appDisplayName ||
        json['app'] == 'MUSCLEMORY' ||
        json['app'] == 'MuscleMemory';
    if (!supportedApp || (version != 1 && version != 2 && version != 3)) {
      throw const FormatException('Unsupported SETKEEP backup');
    }
    if (json['workouts'] is! List) {
      throw const FormatException('Invalid workout backup');
    }
    final settingsSource = json['settings'];
    if (settingsSource != null && settingsSource is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup settings');
    }
    final settings = settingsSource as Map<String, dynamic>? ?? const {};
    return SetkeepBackup(
      workouts: decodeWorkoutItems(json['workouts']),
      workoutTemplates: version == 1
          ? const []
          : decodeWorkoutTemplates(json['workoutTemplates']),
      bodyWeights: version == 3 && json['bodyWeights'] is List
          ? (json['bodyWeights'] as List)
                .map(BodyWeightEntry.tryFromJson)
                .whereType<BodyWeightEntry>()
                .toList()
          : const [],
      customExercises: version == 1
          ? const []
          : decodeExerciseTemplates(json['customExercises']),
      customGyms: version == 1
          ? const []
          : decodeCustomGyms(json['customGyms']),
      selectedGym: settings['selectedGym'] as String?,
      restTimerEnabled: settings['restTimerEnabled'] as bool?,
      restTimerSeconds: settings['restTimerSeconds'] as int?,
      completionCheckEnabled: settings['completionCheckEnabled'] as bool?,
      workoutTimerEnabled: settings['workoutTimerEnabled'] as bool?,
      workoutDurationEnabled: settings['workoutDurationEnabled'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': appDisplayName,
    'version': 3,
    'exportedAt': DateTime.now().toIso8601String(),
    'workouts': workouts.map((item) => item.toJson()).toList(),
    'workoutTemplates': workoutTemplates.map((item) => item.toJson()).toList(),
    'bodyWeights': bodyWeights.map((item) => item.toJson()).toList(),
    'customExercises': customExercises.map((item) => item.toJson()).toList(),
    'customGyms': customGyms,
    'settings': {
      'selectedGym': selectedGym,
      'restTimerEnabled': restTimerEnabled,
      'restTimerSeconds': restTimerSeconds,
      'completionCheckEnabled': completionCheckEnabled,
      'workoutTimerEnabled': workoutTimerEnabled,
      'workoutDurationEnabled': workoutDurationEnabled,
    },
  };
}

class ExerciseTemplate {
  const ExerciseTemplate({
    required this.name,
    this.exerciseId,
    this.distanceUnit = 'km',
    required this.bodyPart,
    required this.equipment,
    required this.startWeight,
    this.startReps = 10,
    this.recordType = ExerciseRecordType.weightReps,
  });

  final String name;
  final String? exerciseId;
  final String distanceUnit;
  String get identity => exerciseIdentity(exerciseId, name);
  final String bodyPart;
  final String equipment;
  final double startWeight;
  final int startReps;
  final ExerciseRecordType recordType;

  String get displayEquipment => equipment;
  ExerciseFormDefinition? get definition =>
      exerciseId == null ? null : ExerciseFormCatalog.byId[exerciseId];
  List<String> get tags => definition?.tags ?? const [];
  bool matchesQuery(String query) => [
    name,
    definition?.englishName ?? '',
    definition?.category ?? '',
    ...?definition?.aliases,
    equipment,
    bodyPart,
    ...tags,
  ].any((value) => value.toLowerCase().contains(query.toLowerCase()));
  ExerciseTemplate withId(String id) => ExerciseTemplate(
    exerciseId: id,
    name: name,
    bodyPart: bodyPart,
    equipment: equipment,
    distanceUnit: distanceUnit,
    startWeight: startWeight,
    startReps: startReps,
    recordType: recordType,
  );
  factory ExerciseTemplate.fromForm(ExerciseFormDefinition form) =>
      ExerciseTemplate(
        exerciseId: form.exerciseId,
        name: form.exerciseName,
        bodyPart: form.category == '腹筋' ? '腹' : form.category,
        equipment: form.equipmentLabel,
        distanceUnit: form.distanceUnit,
        startWeight:
            form.startWeight ??
            (form.loadMode == 'external' && form.recordType == 'weightReps'
                ? 10
                : 0),
        startReps: form.startReps ?? 10,
        recordType: ExerciseRecordType.fromName(form.recordType),
      );

  factory ExerciseTemplate.fromJson(Map<String, dynamic> json) =>
      ExerciseTemplate(
        name: json['name'] as String,
        exerciseId: json['exerciseId'] as String?,
        distanceUnit: json['distanceUnit'] as String? ?? 'km',
        bodyPart: json['bodyPart'] as String,
        equipment: json['equipment'] as String? ?? 'カスタム',
        startWeight: (json['startWeight'] as num?)?.toDouble() ?? 10,
        startReps: json['startReps'] as int? ?? 10,
        recordType: json['recordType'] == null
            ? inferRecordType(
                name: json['name'] as String,
                bodyPart: json['bodyPart'] as String,
                equipment: json['equipment'] as String? ?? 'カスタム',
              )
            : ExerciseRecordType.fromName(json['recordType'] as String?),
      );

  static ExerciseTemplate? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final exercise = ExerciseTemplate.fromJson(source);
      if (exercise.name.trim().isEmpty || exercise.bodyPart.trim().isEmpty) {
        return null;
      }
      return exercise;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'bodyPart': bodyPart,
    'equipment': equipment,
    'startWeight': startWeight,
    'startReps': startReps,
    if (exerciseId != null) 'exerciseId': exerciseId,
    'distanceUnit': distanceUnit,
    'recordType': recordType.name,
  };
}

class CustomExercisePreference {
  CustomExercisePreference._();

  static const _storageKey = 'custom_exercises';
  static List<ExerciseTemplate> exercises = [];

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      exercises = [];
      return;
    }
    try {
      exercises = decodeExerciseTemplates(jsonDecode(encoded));
    } catch (_) {
      exercises = [];
    }
  }

  static String _signature(ExerciseTemplate e) => jsonEncode([
    e.name.trim().toLowerCase(),
    e.equipment.trim().toLowerCase(),
  ]);

  static bool containsDefinition(
    ExerciseTemplate exercise, {
    String? excludingId,
  }) => [...exerciseTemplates, ...exercises].any(
    (e) =>
        (excludingId == null || e.exerciseId != excludingId) &&
        _signature(e) == _signature(exercise),
  );

  // Compatibility entrypoint for older callers. New editors check name + equipment.
  static bool containsName(String name, {String? excludingName}) =>
      [...exerciseTemplates, ...exercises].any(
        (e) =>
            e.name != excludingName &&
            e.name.toLowerCase() == name.trim().toLowerCase(),
      );

  static Future<bool> add(ExerciseTemplate exercise) async {
    if (containsDefinition(exercise) ||
        exercises.any((e) => e.identity == exercise.identity)) {
      return false;
    }
    await replaceAll([...exercises, exercise]);
    return true;
  }

  static Future<bool> update(
    String originalIdentity,
    ExerciseTemplate exercise,
  ) async {
    final matches = exercises
        .where(
          (e) =>
              e.identity == originalIdentity ||
              e.exerciseId == originalIdentity,
        )
        .toList();
    // Old callers may supply a name, but ambiguous names must never select the first row.
    final candidates = matches.isNotEmpty
        ? matches
        : exercises.where((e) => e.name == originalIdentity).toList();
    if (candidates.length != 1) return false;
    final original = candidates.single;
    final id = original.exerciseId ?? legacyCustomExerciseId(original);
    final updated = exercise.withId(id);
    if (exercises.any(
      (e) =>
          e.identity != original.identity &&
          _signature(e) == _signature(updated),
    )) {
      return false;
    }
    await replaceAll(
      exercises
          .map((e) => e.identity == original.identity ? updated : e)
          .toList(),
    );
    return true;
  }

  static Future<void> remove(ExerciseTemplate exercise) async => replaceAll(
    exercises.where((e) => e.identity != exercise.identity).toList(),
  );

  static Future<void> replaceAll(List<ExerciseTemplate> updated) async {
    final unique = <String, ExerciseTemplate>{};
    for (final source in updated) {
      if (source.name.trim().isEmpty) continue;
      final exercise = source.exerciseId == null
          ? source.withId(legacyCustomExerciseId(source))
          : source;
      unique.putIfAbsent(exercise.identity, () => exercise);
    }
    final result = unique.values.toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(result.map((e) => e.toJson()).toList()),
    );
    exercises = result;
  }
}

// Deterministic, collision-free ID for legacy custom definitions. Re-reading the
// same backup produces the same ID without rewriting any name-only history.
String legacyCustomExerciseId(ExerciseTemplate e) =>
    'custom_legacy_${base64Url.encode(utf8.encode(jsonEncode([e.name, e.bodyPart, e.equipment]))).replaceAll('=', '')}';
String newCustomExerciseId() =>
    'custom_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';

const _legacyExerciseTemplates = [
  ExerciseTemplate(
    name: 'ベンチプレス',
    bodyPart: '胸',
    equipment: 'フリーウェイト',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'インクラインダンベルプレス',
    bodyPart: '胸',
    equipment: 'ダンベル',
    startWeight: 20,
  ),
  ExerciseTemplate(
    name: 'ラットプルダウン',
    bodyPart: '背中',
    equipment: 'マシン',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'スクワット',
    bodyPart: '脚',
    equipment: 'フリーウェイト',
    startWeight: 40,
  ),
  ExerciseTemplate(
    name: 'ショルダープレス',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 12,
  ),
  ExerciseTemplate(
    name: 'アームカール',
    bodyPart: '腕',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'チェストプレス',
    bodyPart: '胸',
    equipment: 'マシン',
    startWeight: 30,
  ),
  ExerciseTemplate(
    name: 'ダンベルフライ',
    bodyPart: '胸',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'デッドリフト',
    bodyPart: '背中',
    equipment: 'フリーウェイト',
    startWeight: 50,
  ),
  ExerciseTemplate(
    name: 'バーベルロウ',
    bodyPart: '背中',
    equipment: 'フリーウェイト',
    startWeight: 30,
  ),
  ExerciseTemplate(
    name: 'シーテッドロウ',
    bodyPart: '背中',
    equipment: 'マシン',
    startWeight: 30,
  ),
  ExerciseTemplate(
    name: '懸垂',
    bodyPart: '背中',
    equipment: '自重',
    startWeight: 0,
    recordType: ExerciseRecordType.bodyweightReps,
  ),
  ExerciseTemplate(
    name: 'レッグプレス',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 60,
  ),
  ExerciseTemplate(
    name: 'レッグエクステンション',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 25,
  ),
  ExerciseTemplate(
    name: 'レッグカール',
    bodyPart: '脚',
    equipment: 'マシン',
    startWeight: 20,
  ),
  ExerciseTemplate(
    name: 'ブルガリアンスクワット',
    bodyPart: '脚',
    equipment: 'ダンベル',
    startWeight: 10,
  ),
  ExerciseTemplate(
    name: 'サイドレイズ',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 5,
  ),
  ExerciseTemplate(
    name: 'リアレイズ',
    bodyPart: '肩',
    equipment: 'ダンベル',
    startWeight: 5,
  ),
  ExerciseTemplate(
    name: 'トライセプスプッシュダウン',
    bodyPart: '腕',
    equipment: 'ケーブル',
    startWeight: 15,
  ),
  ExerciseTemplate(
    name: 'ハンマーカール',
    bodyPart: '腕',
    equipment: 'ダンベル',
    startWeight: 8,
  ),
  ExerciseTemplate(
    name: 'クランチ',
    bodyPart: '腹',
    equipment: '自重',
    startWeight: 0,
    startReps: 15,
    recordType: ExerciseRecordType.bodyweightReps,
  ),
  ExerciseTemplate(
    name: 'シットアップ',
    bodyPart: '腹',
    equipment: '自重',
    startWeight: 0,
    startReps: 15,
    recordType: ExerciseRecordType.bodyweightReps,
  ),
  ExerciseTemplate(
    name: '腕立て伏せ',
    bodyPart: '胸',
    equipment: '自重',
    startWeight: 0,
    startReps: 10,
    recordType: ExerciseRecordType.bodyweightReps,
  ),
  ExerciseTemplate(
    name: 'ディップス',
    bodyPart: '胸',
    equipment: '自重',
    startWeight: 0,
    startReps: 10,
    recordType: ExerciseRecordType.bodyweightReps,
  ),
  ExerciseTemplate(
    name: 'プランク',
    bodyPart: '腹',
    equipment: '自重',
    startWeight: 0,
    startReps: 60,
    recordType: ExerciseRecordType.timed,
  ),
  ExerciseTemplate(
    name: 'サイドプランク',
    bodyPart: '腹',
    equipment: '自重',
    startWeight: 0,
    startReps: 45,
    recordType: ExerciseRecordType.timed,
  ),
  ExerciseTemplate(
    name: 'ウォールシット',
    bodyPart: '脚',
    equipment: '自重',
    startWeight: 0,
    startReps: 60,
    recordType: ExerciseRecordType.timed,
  ),
  ExerciseTemplate(
    name: 'トレッドミル',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
    recordType: ExerciseRecordType.cardio,
  ),
  ExerciseTemplate(
    name: 'エアロバイク',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
    recordType: ExerciseRecordType.cardio,
  ),
  ExerciseTemplate(
    name: 'クロストレーナー',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
    recordType: ExerciseRecordType.cardio,
  ),
  ExerciseTemplate(
    name: 'ステアクライマー',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
    recordType: ExerciseRecordType.cardio,
  ),
  ExerciseTemplate(
    name: 'ローイングマシン',
    bodyPart: '有酸素',
    equipment: 'マシン',
    startWeight: 1,
    startReps: 10,
    recordType: ExerciseRecordType.cardio,
  ),
  ExerciseTemplate(
    name: 'ランニング',
    bodyPart: '有酸素',
    equipment: 'その他',
    startWeight: 0,
    startReps: 30,
    recordType: ExerciseRecordType.distance,
  ),
  ExerciseTemplate(
    name: 'ウォーキング',
    bodyPart: '有酸素',
    equipment: 'その他',
    startWeight: 0,
    startReps: 30,
    recordType: ExerciseRecordType.distance,
  ),
  ExerciseTemplate(
    name: 'サイクリング',
    bodyPart: '有酸素',
    equipment: 'その他',
    startWeight: 0,
    startReps: 30,
    recordType: ExerciseRecordType.distance,
  ),
];

// Only catalog entries appear in the new picker. Legacy definitions remain for
// reading name-only records and drafts; they are never assigned a variant ID.
final exerciseTemplates = ExerciseFormCatalog.entries
    .where((form) => form.selectable)
    .map(ExerciseTemplate.fromForm)
    .toList(growable: false);

class ExerciseSelection {
  const ExerciseSelection(this.template, {this.savedSets});
  final ExerciseTemplate template;
  final List<RecordedSet>? savedSets;
}

class ExerciseFavoritePreference {
  ExerciseFavoritePreference._();
  static const _key = 'favorite_exercise_identities';

  static Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? const <String>[])
        .map(canonicalExerciseIdentity)
        .toSet();
  }

  static Future<void> save(Set<String> identities) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setStringList(_key, identities.toList()..sort())) {
      throw StateError('Favorites could not be saved');
    }
  }
}

String exerciseSortKey(String name) => String.fromCharCodes(
  name.toLowerCase().runes.map(
    (rune) => rune >= 0x30A1 && rune <= 0x30F6 ? rune - 0x60 : rune,
  ),
);

/// The keyboard inset is applied once, before sizing the picker. Use all
/// remaining height while typing rather than shrinking it by another 18%.
class ExercisePickerViewport extends StatelessWidget {
  const ExercisePickerViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: FractionallySizedBox(
        heightFactor: keyboard > 0 ? 1 : 0.82,
        child: Column(
          children: [
            if (keyboard == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withAlpha(100),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({
    super.key,
    this.existingIdentities = const {},
    this.existingNames = const {},
    this.menus = const [],
    this.gymStoreId,
    this.customPlaceId,
  });
  final String? gymStoreId;
  final String? customPlaceId;
  final Set<String> existingIdentities;
  // Compatibility for old name-only callers; never use names for ID variants.
  final Set<String> existingNames;
  final List<SavedWorkoutTemplate> menus;
  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  bool _storeOnly = false, _storeLoading = false, _storeFailed = false;
  Set<String>? _storeIds;
  List<GymExerciseEvidence> _storeEvidence = [];
  int _storeRequest = 0;
  Future<void> _filterStore(bool enabled) async {
    final request = ++_storeRequest;
    if (!enabled) {
      setState(() {
        _storeOnly = false;
        _storeLoading = false;
      });
      return;
    }
    if (_storeIds != null) {
      setState(() => _storeOnly = true);
      return;
    }
    setState(() {
      _storeLoading = true;
      _storeFailed = false;
    });
    try {
      final evidence = widget.gymStoreId != null
          ? (await GymEquipmentCache.load(
              GymServices.repository,
              GymStore(id: widget.gymStoreId!, chainName: '', name: '店舗'),
            )).evidence
          : await GymServices.repository.privateEvidence(widget.customPlaceId!);
      final ids = availableForms(evidence.map((e) => e.exerciseId))
          .map((f) => f.exerciseId)
          .toSet();
      if (mounted && request == _storeRequest) {
        setState(() {
          _storeIds = ids;
          _storeEvidence = evidence;
          _storeOnly = true;
        });
      }
    } catch (_) {
      if (mounted && request == _storeRequest) {
        setState(() => _storeFailed = true);
      }
    } finally {
      if (mounted && request == _storeRequest) {
        setState(() => _storeLoading = false);
      }
    }
  }

  static const _categories = ['胸', '背中', '肩', '腕', '脚', '腹', '有酸素', 'HYROX'];
  String _query = '';
  String? _selectedCategory;
  bool _showMenus = false;
  SavedWorkoutTemplate? _activeMenu;
  final _searchController = TextEditingController();
  Set<String> _favorites = {};
  bool _favoritesReady = false;
  bool _savingFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await ExerciseFavoritePreference.load();
      if (mounted) {
        setState(() {
          _favorites = favorites;
          _favoritesReady = true;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('お気に入りを読み込めませんでした。開き直してください。')),
        );
      }
    }
  }

  Future<void> _toggleFavorite(String identity) async {
    if (!_favoritesReady || _savingFavorite) return;
    final updated = {..._favorites};
    if (!updated.remove(identity)) updated.add(identity);
    setState(() => _savingFavorite = true);
    try {
      await ExerciseFavoritePreference.save(updated);
      if (mounted) setState(() => _favorites = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('お気に入りを保存できませんでした。')));
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  final _listController = ScrollController();

  @override
  void dispose() {
    _listController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  final Map<String, ExerciseSelection> _selected = {};
  final List<String> _order = [];
  String _categoryLabel(String category) => category == '腹' ? '腹筋' : category;
  List<ExerciseTemplate> get _catalog => <String, ExerciseTemplate>{
    for (final item in exerciseTemplates) item.identity: item,
    // A formerly custom exercise keeps its saved recording settings when a
    // later release adds a built-in exercise with the same name.
    for (final item in CustomExercisePreference.exercises) item.identity: item,
  }.values.toList();

  List<ExerciseSelection> get _source {
    if (_activeMenu != null) return _menuItems(_activeMenu!);
    if (_showMenus) return const [];
    return _catalog
        .where(
          (e) => _selectedCategory == null || e.bodyPart == _selectedCategory,
        )
        .map((e) => _selected[e.identity] ?? ExerciseSelection(e))
        .toList();
  }

  List<ExerciseSelection> _menuItems(SavedWorkoutTemplate menu) {
    return menu.exerciseGroups.values.map((sets) {
      final first = sets.first;
      final known = _catalog.where((e) => e.identity == first.identity);
      return ExerciseSelection(
        known.isNotEmpty
            ? known.first
            : ExerciseTemplate(
                exerciseId: first.exerciseId,
                name: first.exerciseName,
                bodyPart: first.bodyPart,
                equipment: first.equipment.isEmpty ? 'マイメニュー' : first.equipment,
                distanceUnit: first.distanceUnit,
                startWeight: first.weight,
                startReps: first.reps,
                recordType: first.recordType,
              ),
        savedSets: sets,
      );
    }).toList();
  }

  bool _alreadyAdded(ExerciseTemplate item) =>
      widget.existingIdentities
          .map(canonicalExerciseIdentity)
          .contains(item.identity) ||
      (item.exerciseId == null && widget.existingNames.contains(item.name));

  void _toggle(ExerciseSelection item) {
    if (_alreadyAdded(item.template)) return;
    setState(() {
      final identity = item.template.identity;
      if (_selected.remove(identity) != null) {
        _order.remove(identity);
      } else {
        _selected[identity] = item;
        _order.add(identity);
      }
    });
  }

  void _selectMenu(SavedWorkoutTemplate menu) {
    setState(() {
      _activeMenu = menu;
      _query = '';
      _searchController.clear();
      for (final item in _menuItems(menu)) {
        if (_storeOnly &&
            !(_storeIds?.contains(item.template.exerciseId) ?? false)) {
          continue;
        }
        final identity = item.template.identity;
        if (_alreadyAdded(item.template) || _selected.containsKey(identity)) {
          continue;
        }
        _selected[identity] = item;
        _order.add(identity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final menuList = _showMenus && _activeMenu == null;
    final background =
        Theme.of(context).bottomSheetTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    Widget fixedArea(String key, Widget child) => ColoredBox(
      key: Key(key),
      color: background.withAlpha(255),
      child: child,
    );
    final browsing =
        _selectedCategory != null || _showMenus || _query.isNotEmpty;
    final filtered = _source.where((item) {
      final e = item.template;
      if (_storeOnly && !(_storeIds?.contains(e.exerciseId) ?? false)) {
        return false;
      }
      final query = _query.toLowerCase();
      return e.matchesQuery(query) ||
          exerciseDisplayName(
            e.name,
            exerciseId: e.exerciseId,
          ).toLowerCase().contains(query);
    }).toList();
    filtered.sort((a, b) {
      final af = _favorites.contains(a.template.identity);
      final bf = _favorites.contains(b.template.identity);
      if (af != bf) return af ? -1 : 1;
      final name = exerciseSortKey(a.template.name)
          .compareTo(exerciseSortKey(b.template.name));
      return name != 0
          ? name
          : a.template.identity.compareTo(b.template.identity);
    });
    return SafeArea(
      child: Column(
        children: [
          fixedArea(
            'exercisePickerHeader',
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                child: Row(
                  children: [
                    if (browsing)
                      IconButton(
                        key: const Key('backToExerciseCategories'),
                        onPressed: () => setState(() {
                          if (_activeMenu != null) {
                            _activeMenu = null;
                          } else {
                            _selectedCategory = null;
                            _showMenus = false;
                          }
                          _searchController.clear();
                          _query = '';
                        }),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: Text(
                        _activeMenu?.name ??
                            (_showMenus
                                ? 'マイメニュー'
                                : (_selectedCategory == null
                                      ? '部位・カテゴリを選択'
                                      : '${_categoryLabel(_selectedCategory!)}の種目')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (_storeOnly && widget.gymStoreId != null && !menuList)
                      IconButton(
                        key: const Key('reportStoreExercises'),
                        tooltip: '対応種目を報告',
                        icon: const Icon(Icons.outlined_flag, size: 20),
                        onPressed: () => showStoreExerciseReport(
                          context,
                          widget.gymStoreId!,
                          _storeIds ?? {},
                        ),
                      ),
                    if (_selectedCategory != null)
                      IconButton(
                        key: const Key('addCustomExerciseForCategory'),
                        tooltip: '${_categoryLabel(_selectedCategory!)}の種目を作る',
                        onPressed: _createCustomExercise,
                        icon: const Icon(Icons.add_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if ((widget.gymStoreId != null || widget.customPlaceId != null) &&
              !menuList)
            fixedArea(
              'exercisePickerStoreFilter',
              Column(
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('全種目'),
                        selected: !_storeOnly,
                        onSelected: (_) => _filterStore(false),
                      ),
                      ChoiceChip(
                        key: const Key('storeExerciseFilter'),
                        visualDensity: VisualDensity.compact,
                        tooltip: '登録設備から可能な種目だけ表示します',
                        label: Text(
                          widget.gymStoreId != null ? 'この店舗でできる' : 'この場所でできる',
                        ),
                        selected: _storeOnly,
                        onSelected: _storeLoading
                            ? null
                            : (_) => _filterStore(true),
                      ),
                    ],
                  ),
                  if (_storeLoading) const LinearProgressIndicator(),
                ],
              ),
            ),
          if (!menuList)
            fixedArea(
              'exercisePickerSearchArea',
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: TextField(
                  controller: _searchController,
                  key: const Key('exerciseSearchField'),
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '種目名・器具で検索',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('clearExerciseSearch'),
                            tooltip: '検索をクリア',
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ClipRect(
              key: const Key('exercisePickerListClip'),
              child: Material(
                color: background.withAlpha(255),
                child: ListView(
                  controller: _listController,
                  key: ValueKey(
                    'exercisePickerList${_activeMenu?.name ?? (_showMenus ? 'menus' : _selectedCategory)}${_query.isNotEmpty}',
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    if (_storeFailed)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('対応種目を取得できませんでした。「全種目」からも追加できます。'),
                      ),
                    if (!_storeFailed &&
                        _storeOnly &&
                        (_storeIds?.isEmpty ?? true))
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'この店舗の設備情報は未取得、または対応種目の登録がまだありません。「全種目」から追加できます。',
                        ),
                      ),
                    if (_storeOnly && (_storeIds?.isEmpty ?? true))
                      TextButton(
                        key: const Key('showAllStoreExercises'),
                        onPressed: () => _filterStore(false),
                        child: const Text('全種目を見る'),
                      ),
                    if (!browsing) ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          key: const Key('exercisePickerMyMenuEntry'),
                          leading: const Icon(Icons.playlist_add_rounded),
                          title: const Text('マイメニュー'),
                          subtitle: Text('${widget.menus.length}メニュー'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => setState(() => _showMenus = true),
                        ),
                      ),
                      ..._categories.map(
                        (category) => BodyPartCategoryCard(
                          category: category,
                          label: _categoryLabel(category),
                          count: _catalog
                              .where(
                                (e) =>
                                    e.bodyPart == category &&
                                    (!_storeOnly ||
                                        (_storeIds?.contains(e.exerciseId) ??
                                            false)),
                              )
                              .length,
                          onTap: () =>
                              setState(() => _selectedCategory = category),
                        ),
                      ),
                    ],
                    if (menuList) ...[
                      if (widget.menus.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('保存したマイメニューはありません'),
                        ),
                      for (final menu in widget.menus)
                        ListTile(
                          key: ValueKey('pickMenu${menu.name}'),
                          title: Text(menu.name),
                          subtitle: Text('${menu.exerciseGroups.length}種目'),
                          leading: const Icon(Icons.playlist_add_rounded),
                          onTap: () => _selectMenu(menu),
                        ),
                    ],
                    if (browsing && !menuList)
                      ...filtered.map((item) {
                        final e = item.template;
                        final added = _alreadyAdded(e);
                        return ListTile(
                          key: ValueKey(
                            'selectExercise${e.exerciseId ?? e.name}',
                          ),
                          contentPadding: const EdgeInsetsDirectional.only(
                            start: 8,
                            end: 4,
                          ),
                          horizontalTitleGap: 8,
                          minVerticalPadding: 8,
                          selected: added || _selected.containsKey(e.identity),
                          selectedTileColor: FamilyPalette.of(context).soft,
                          selectedColor: const Color(0xFF101820),
                          leading: ExerciseListThumbnail(
                            exerciseId: e.exerciseId,
                          ),
                          title: Text(
                            exerciseDisplayName(
                              e.name,
                              exerciseId: e.exerciseId,
                              languageCode: Localizations.localeOf(context)
                                  .languageCode,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            added ? '追加済み' : '${e.bodyPart} ・ ${e.equipment}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey('favoriteExercise${e.identity}'),
                                tooltip: _favorites.contains(e.identity)
                                    ? 'お気に入り解除'
                                    : 'お気に入りに追加',
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: !_favoritesReady || _savingFavorite
                                    ? null
                                    : () => _toggleFavorite(e.identity),
                                icon: Icon(
                                  _favorites.contains(e.identity)
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                ),
                              ),
                              IconButton(
                                key: Key(
                                  'exerciseDetails${e.exerciseId ?? e.name}',
                                ),
                                tooltip: '種目詳細を見る',
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.info_outline_rounded),
                                onPressed: () => _showExerciseMuscles(e),
                              ),
                            ],
                          ),
                          onTap: added ? null : () => _toggle(item),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
          fixedArea(
            'exercisePickerFooter',
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, typing ? 4 : 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!typing)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selected.length}種目選択中',
                            key: const Key('selectedExerciseCount'),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('addSelectedExercises'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _order
                                  .where(_selected.containsKey)
                                  .map((name) => _selected[name]!)
                                  .toList(),
                            ),
                      child: const Text('選択した種目を追加'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createCustomExercise() async {
    final category = _selectedCategory;
    if (category == null) return;
    final created = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) => _ExerciseEditorDialog(fixedBodyPart: category),
    );
    if (created == null) return;
    final added = await CustomExercisePreference.add(created);
    if (mounted && added) {
      setState(() {
        _selected[created.identity] = ExerciseSelection(created);
        _order.add(created.identity);
        _selectedCategory = created.bodyPart;
        _query = '';
        _searchController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _listController.hasClients) {
          _listController.jumpTo(0);
        }
      });
    }
  }

  List<GymExerciseEvidence> _evidenceFor(ExerciseTemplate e) => _storeEvidence
      .where(
        (r) =>
            ExerciseFormCatalog.canonicalDefinition(r.exerciseId)?.exerciseId ==
            e.exerciseId,
      )
      .toList();

  Future<void> _showExerciseMuscles(ExerciseTemplate template) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExerciseMuscleDetailPage(
          exercise: template,
          storeEvidence: _storeOnly ? _evidenceFor(template) : const [],
        ),
      ),
    );
  }
}

class ExerciseMuscleDetailPage extends StatelessWidget {
  const ExerciseMuscleDetailPage({
    super.key,
    required this.exercise,
    this.storeEvidence = const [],
  });
  final List<GymExerciseEvidence> storeEvidence;

  final ExerciseTemplate exercise;

  @override
  Widget build(BuildContext context) {
    final profile = muscleProfileForExercise(
      exercise.name,
      exercise.bodyPart,
      exerciseId: exercise.exerciseId,
    );
    final form = ExerciseFormCatalog.resolve(
      exercise.exerciseId,
      exercise.name,
    );
    final media = ExerciseMediaCatalog.forExerciseId(exercise.exerciseId);
    final primaryLabels = form != null
        ? form.primaryMuscleLabels
        : profile.primary.map((muscle) => muscle.label).toList();
    final secondaryLabels = form != null
        ? form.secondaryMuscleLabels
        : profile.secondary.map((muscle) => muscle.label).toList();
    final scores = <MuscleRegion, double>{
      for (final muscle in profile.primary) muscle: 1,
      for (final muscle in profile.secondary) muscle: 0.35,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          exerciseDisplayName(exercise.name, exerciseId: exercise.exerciseId),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (storeEvidence.isNotEmpty) ...[
            const Text('この店舗で使用可能'),
            GymEvidenceList(evidence: storeEvidence),
          ],
          if (media != null)
            ExerciseMediaFormView(
              key: ValueKey(exercise.identity),
              media: media,
              fallback: _formUnavailable('フォームガイド動画を再生できませんでした'),
            )
          else if (form?.available == true)
            _formUnavailable('この種目のフォームガイド動画を確認中です')
          else
            _muscleTargetGuide(scores),
          const SizedBox(height: 18),
          const Text(
            '主に使う筋肉',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: primaryLabels
                .map(
                  (muscle) => Chip(
                    avatar: const CircleAvatar(
                      backgroundColor: Color(0xFFD4162A),
                    ),
                    label: Text(muscle),
                  ),
                )
                .toList(),
          ),
          if (secondaryLabels.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '補助的に使う筋肉',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: secondaryLabels
                  .map(
                    (muscle) => Chip(
                      avatar: const CircleAvatar(
                        backgroundColor: Color(0xFFFF8B91),
                      ),
                      label: Text(muscle),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            (form?.available == true)
                ? '濃い赤がメインターゲット、薄い赤が補助的に使う筋肉です。対象筋の説明で、筋活動の実測値ではありません。'
                : '濃い赤がメインターゲット、薄い赤が補助的に使う筋肉です。',
            style: const TextStyle(color: Color(0xFF666D68)),
          ),
        ],
      ),
    );
  }

  Widget _formUnavailable(String message) => Padding(
    key: const Key('exerciseFormUnavailable'),
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Text(message, textAlign: TextAlign.center),
  );

  Widget _muscleTargetGuide(Map<MuscleRegion, double> scores) => Container(
    key: const Key('exerciseMuscleModel3D'),
    height: 470,
    decoration: BoxDecoration(
      color: const Color(0xFF091219),
      borderRadius: BorderRadius.circular(24),
    ),
    clipBehavior: Clip.antiAlias,
    child: MuscleMannequinView(
      tapToFlip: false,
      scores: scores,
      fallbackBodyPartCounts: {exercise.bodyPart: 1},
    ),
  );
}

class CustomExerciseManagementPage extends StatefulWidget {
  const CustomExerciseManagementPage({super.key});

  @override
  State<CustomExerciseManagementPage> createState() =>
      _CustomExerciseManagementPageState();
}

class _CustomExerciseManagementPageState
    extends State<CustomExerciseManagementPage> {
  Future<void> _addExercise() async {
    final exercise = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) => const _ExerciseEditorDialog(),
    );
    if (exercise == null) return;
    final added = await CustomExercisePreference.add(exercise);
    if (mounted && added) setState(() {});
  }

  Future<void> _editExercise(ExerciseTemplate exercise) async {
    final updated = await showDialog<ExerciseTemplate>(
      context: context,
      builder: (_) => _ExerciseEditorDialog(initial: exercise),
    );
    if (updated == null) return;
    final saved = await CustomExercisePreference.update(
      exercise.identity,
      updated,
    );
    if (mounted && saved) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「${updated.name}」を更新しました')));
    }
  }

  Future<void> _deleteExercise(ExerciseTemplate exercise) async {
    final messenger = ScaffoldMessenger.of(context);
    await CustomExercisePreference.remove(exercise);
    if (!mounted) return;
    setState(() {});
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${exercise.name}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = await CustomExercisePreference.add(exercise);
              if (!mounted || !restored) return;
              setState(() {});
              messenger.showSnackBar(
                SnackBar(content: Text('「${exercise.name}」を元に戻しました')),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final exercises = CustomExercisePreference.exercises;
    return Scaffold(
      appBar: AppBar(
        title: const Text('カスタム種目管理'),
        actions: [
          IconButton(
            key: const Key('addCustomExerciseButton'),
            tooltip: 'カスタム種目を追加',
            onPressed: _addExercise,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: exercises.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fitness_center_rounded,
                      size: 48,
                      color: Color(0xFF777F78),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'カスタム種目はまだありません',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('種目を作る'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: exercises.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return Card(
                  key: Key('customExercise$index'),
                  child: ListTile(
                    title: Text(
                      exerciseDisplayName(
                        exercise.name,
                        exerciseId: exercise.exerciseId,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      exercise.recordType.hasWeightInput
                          ? '${exercise.bodyPart} ・ ${exercise.equipment} ・ ${formatWeight(exercise.startWeight)}kg × ${exercise.startReps}回'
                          : '${exercise.bodyPart} ・ ${exercise.equipment} ・ ${exercise.recordType.label}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '${exercise.name}を編集',
                          onPressed: () => _editExercise(exercise),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '${exercise.name}を削除',
                          onPressed: () => _deleteExercise(exercise),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ExerciseEditorDialog extends StatefulWidget {
  const _ExerciseEditorDialog({this.initial, this.fixedBodyPart});

  final ExerciseTemplate? initial;
  final String? fixedBodyPart;

  @override
  State<_ExerciseEditorDialog> createState() => _ExerciseEditorDialogState();
}

class _ExerciseEditorDialogState extends State<_ExerciseEditorDialog> {
  late final String _exerciseId =
      widget.initial?.exerciseId ?? newCustomExerciseId();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late String _bodyPart;
  late String _equipment;
  late ExerciseRecordType _recordType;

  static const _bodyParts = ['胸', '背中', '脚', '肩', '腕', '腹', '有酸素', 'HYROX'];

  List<ExerciseRecordType> get _editableRecordTypes {
    const visible = [
      ExerciseRecordType.weightReps,
      ExerciseRecordType.bodyweightReps,
      ExerciseRecordType.cardio,
    ];
    if (_bodyPart == 'HYROX') return ExerciseRecordType.values;
    final initialType = widget.initial?.recordType;
    if (initialType != null && !visible.contains(initialType)) {
      return [...visible, initialType];
    }
    return visible;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _weightController = TextEditingController(
      text: formatWeight(initial?.startWeight ?? 10),
    );
    _repsController = TextEditingController(
      text: (initial?.startReps ?? 10).toString(),
    );
    _bodyPart = widget.fixedBodyPart ?? initial?.bodyPart ?? '胸';
    _equipment = initial == null
        ? 'マシン'
        : exerciseEquipmentOptions.contains(initial.equipment)
        ? initial.equipment
        : 'その他';
    _recordType =
        initial?.recordType ??
        (_bodyPart == '有酸素'
            ? ExerciseRecordType.cardio
            : ExerciseRecordType.weightReps);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '種目名を入力してください';
    if (CustomExercisePreference.containsDefinition(
      ExerciseTemplate(
        name: name,
        bodyPart: _bodyPart,
        equipment: _equipment,
        startWeight: 0,
      ),
      excludingId: widget.initial?.exerciseId,
    )) {
      return '同じ名前・器具の種目があります';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ExerciseTemplate(
        exerciseId: _exerciseId,
        distanceUnit:
            widget.initial?.distanceUnit ?? (_bodyPart == 'HYROX' ? 'm' : 'km'),
        name: _nameController.text.trim(),
        bodyPart: _bodyPart,
        equipment: _equipment,
        startWeight: double.parse(_weightController.text),
        startReps: int.parse(_repsController.text),
        recordType: _recordType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新しい種目' : 'カスタム種目を編集'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('customExerciseNameField'),
                controller: _nameController,
                autofocus: true,
                maxLength: 40,
                validator: _validateName,
                decoration: const InputDecoration(labelText: '種目名'),
              ),
              if (widget.fixedBodyPart == null)
                DropdownButtonFormField<String>(
                  key: const Key('customExerciseBodyPartField'),
                  initialValue: _bodyPart,
                  decoration: const InputDecoration(labelText: '鍛える部位'),
                  items: _bodyParts
                      .map(
                        (part) =>
                            DropdownMenuItem(value: part, child: Text(part)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _bodyPart = value!;
                    if (_bodyPart == '有酸素') {
                      _recordType = ExerciseRecordType.cardio;
                    } else if (_recordType == ExerciseRecordType.cardio) {
                      _recordType = ExerciseRecordType.weightReps;
                    }
                  }),
                )
              else
                ListTile(
                  key: const Key('inheritedCustomExerciseBodyPart'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('鍛える部位'),
                  subtitle: Text(_bodyPart == '腹' ? '腹筋' : _bodyPart),
                  leading: const Icon(Icons.accessibility_new_rounded),
                ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('customExerciseEquipmentField'),
                initialValue: _equipment,
                decoration: const InputDecoration(labelText: '器具'),
                items: exerciseEquipmentOptions
                    .map(
                      (equipment) => DropdownMenuItem(
                        value: equipment,
                        child: Text(equipment),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _equipment = value!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ExerciseRecordType>(
                key: const Key('customExerciseRecordTypeField'),
                initialValue: _recordType,
                decoration: const InputDecoration(labelText: '記録タイプ'),
                items: _editableRecordTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _recordType = value!),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_recordType == ExerciseRecordType.weightReps)
                    Expanded(
                      child: TextFormField(
                        key: const Key('customExerciseWeightField'),
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final weight = double.tryParse(value ?? '');
                          return weight == null || weight < 0 ? '0以上で入力' : null;
                        },
                        decoration: const InputDecoration(labelText: '初期重量 kg'),
                      ),
                    ),
                  if (_recordType == ExerciseRecordType.weightReps)
                    const SizedBox(width: 10),
                  if (_recordType == ExerciseRecordType.weightReps ||
                      _recordType == ExerciseRecordType.bodyweightReps ||
                      _recordType == ExerciseRecordType.timed)
                    Expanded(
                      child: TextFormField(
                        key: const Key('customExerciseRepsField'),
                        controller: _repsController,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final reps = int.tryParse(value ?? '');
                          return reps == null || reps < 1 ? '1以上で入力' : null;
                        },
                        decoration: InputDecoration(
                          labelText: _recordType == ExerciseRecordType.timed
                              ? '初期時間（秒）'
                              : '初期回数',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('saveCustomExerciseButton'),
          onPressed: _save,
          child: Text(widget.initial == null ? '追加' : '保存'),
        ),
      ],
    );
  }
}

const exerciseEquipmentOptions = [
  'フリーウェイト',
  'ダンベル',
  'マシン',
  'プレートロード',
  'ケーブル',
  '自重',
  'カスタム',
  'その他',
];

String _newWorkoutIdentity() =>
    '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';

class WorkoutExercise {
  WorkoutExercise({
    String? instanceId,
    required this.name,
    this.exerciseId,
    this.distanceUnit = 'km',
    required this.bodyPart,
    required this.equipment,
    required this.recordType,
    required this.sets,
  }) : instanceId = instanceId ?? _newWorkoutIdentity();

  final String instanceId;
  final String name;
  final String? exerciseId;
  final String distanceUnit;
  String get identity => exerciseIdentity(exerciseId, name);
  final String bodyPart;
  final String equipment;
  ExerciseRecordType recordType;
  final List<WorkoutSet> sets;
}

class WorkoutExerciseCardShell extends StatelessWidget {
  const WorkoutExerciseCardShell({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class WorkoutExerciseCardHeader extends StatelessWidget {
  const WorkoutExerciseCardHeader({
    super.key,
    required this.name,
    this.exerciseId,
    required this.bodyPart,
    required this.equipment,
    this.trailing,
    this.titleKey,
    this.containerKey,
  });

  final String name;
  final String? exerciseId;
  final String bodyPart;
  final String equipment;
  final Widget? trailing;
  final Key? titleKey;
  final Key? containerKey;

  @override
  Widget build(BuildContext context) => Container(
    key: containerKey,
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: FamilyPalette.of(context).accent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        ExerciseListThumbnail(exerciseId: exerciseId),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = exerciseDisplayName(
                    name,
                    exerciseId: exerciseId,
                  );
                  const baseStyle = TextStyle(
                    color: Color(0xFF101820),
                    fontWeight: FontWeight.w900,
                  );
                  var fontSize = 16.0;
                  for (final size in [18.0, 17.0, 16.0]) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: title,
                        style: DefaultTextStyle.of(context).style
                            .merge(baseStyle.copyWith(fontSize: size)),
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      locale: Localizations.maybeLocaleOf(context),
                      maxLines: 1,
                      ellipsis: '…',
                    )..layout(maxWidth: constraints.maxWidth);
                    final fits = !painter.didExceedMaxLines;
                    painter.dispose();
                    if (fits) {
                      fontSize = size;
                      break;
                    }
                  }
                  return Text(
                    title,
                    key: titleKey,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: baseStyle.copyWith(fontSize: fontSize),
                  );
                },
              ),
              if (bodyPart.isNotEmpty || equipment.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  [
                    bodyPart,
                    equipment,
                  ].where((value) => value.isNotEmpty).join(' ・ '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF101820),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class ExerciseInputCard extends StatelessWidget {
  const ExerciseInputCard({
    super.key,
    required this.exerciseIndex,
    required this.exercise,
    required this.history,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onRemove,
    required this.onToggleSet,
    required this.onApplyPrevious,
    required this.onSetAllCompleted,
    required this.onValuesChanged,
    this.onRecordTypeChanged,
    this.showCompletionCheck,
    this.numericNodes,
    this.nextNumeric,
  });

  final List<FocusNode> Function(WorkoutSet)? numericNodes;
  final VoidCallback? Function(FocusNode)? nextNumeric;
  final bool? showCompletionCheck;
  final int exerciseIndex;
  final WorkoutExercise exercise;
  final List<WorkoutRecord> history;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final VoidCallback? onRemove;
  final ValueChanged<int> onToggleSet;
  final ValueChanged<List<RecordedSet>> onApplyPrevious;
  final ValueChanged<bool> onSetAllCompleted;
  final VoidCallback onValuesChanged;
  final VoidCallback? onRecordTypeChanged;

  @override
  Widget build(BuildContext context) {
    final previousSets = latestSetsForExercise(
      history,
      exercise.name,
      exerciseId: exercise.exerciseId,
    );
    final completedCount = exercise.sets.where((set) => set.completed).length;
    final allCompleted = completedCount == exercise.sets.length;
    final previousText = previousSets.isEmpty
        ? '前回の記録はありません'
        : '前回  ${previousSets.map((set) => set.displaySummary).join(' ・ ')}';
    return WorkoutExerciseCardShell(
      children: [
        WorkoutExerciseCardHeader(
          containerKey: Key('exerciseInputHeader$exerciseIndex'),
          titleKey: Key('exerciseInputTitle$exerciseIndex'),
          name: exercise.name,
          exerciseId: exercise.exerciseId,
          bodyPart: exercise.bodyPart,
          equipment: exercise.equipment,
          trailing: onRemove == null
              ? null
              : IconButton(
                  tooltip: '種目を削除',
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF101820),
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FamilyPalette.of(context).subtle,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  previousText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (previousSets.isNotEmpty)
                TextButton(
                  key: Key('applyPrevious$exerciseIndex'),
                  onPressed: () => onApplyPrevious(previousSets),
                  child: const Text('反映'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if ((showCompletionCheck ??
                WorkoutUiPreference.completionCheckEnabled) &&
            exercise.recordType.usesSets)
          Row(
            children: [
              Expanded(
                child: Text(
                  '完了 $completedCount / ${exercise.sets.length}',
                  style: const TextStyle(
                    color: Color(0xFF6C746D),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (exercise.sets.isNotEmpty)
                TextButton.icon(
                  key: Key('toggleAllSets$exerciseIndex'),
                  onPressed: () => onSetAllCompleted(!allCompleted),
                  icon: Icon(
                    allCompleted
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    size: 18,
                  ),
                  label: Text(allCompleted ? 'すべて解除' : 'すべて完了'),
                ),
            ],
          ),
        if (exercise.recordType == ExerciseRecordType.bodyweightReps &&
            usesAssistanceWeight(
              exercise.name,
              exerciseId: exercise.exerciseId,
            ))
          TextButton(
            key: Key('addAssistanceWeight$exerciseIndex'),
            onPressed: () {
              exercise.recordType = ExerciseRecordType.assistedReps;
              (onRecordTypeChanged ?? onValuesChanged)();
            },
            child: const Text('補助重量を追加'),
          ),
        if (usesAdditionalWeight(
          exercise.name,
          exerciseId: exercise.exerciseId,
        ))
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('追加重量（kg）・自重のみは0', style: TextStyle(fontSize: 12)),
          ),
        if (exercise.recordType == ExerciseRecordType.assistedReps)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '補助重量（kg）・補助なしは0。軽いほど負荷が高くなります。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        SetHeader(
          recordType: exercise.recordType,
          showCompletionCheck:
              (showCompletionCheck ??
              WorkoutUiPreference.completionCheckEnabled),
        ),
        const SizedBox(height: 8),
        ...List.generate(exercise.sets.length, (setIndex) {
          final set = exercise.sets[setIndex];
          final nodes = numericNodes?.call(set);
          return SetRow(
            key: ObjectKey(set),
            weightFocus: nodes?[0],
            repsFocus: nodes?[1],
            nextWeight: nodes == null ? null : nextNumeric?.call(nodes[0]),
            nextReps: nodes == null ? null : nextNumeric?.call(nodes[1]),
            number: setIndex + 1,
            fieldPrefix: '${exerciseIndex}_',
            set: set,
            recordType: exercise.recordType,
            exerciseName: exercise.name,
            exerciseId: exercise.exerciseId,
            distanceUnit: exercise.distanceUnit,
            showCompletionCheck:
                (showCompletionCheck ??
                    WorkoutUiPreference.completionCheckEnabled) &&
                exercise.recordType.usesSets,
            onWeightChanged: (value) {
              set.weight = value;
              onValuesChanged();
            },
            onRepsChanged: (value) {
              set.reps = value;
              onValuesChanged();
            },
            onDurationChanged: (value) {
              set.durationSeconds = value;
              onValuesChanged();
            },
            onDistanceChanged: (value) {
              set.distanceKm = value;
              onValuesChanged();
            },
            onSpeedChanged: (value) {
              set.speedKmh = value;
              onValuesChanged();
            },
            onInclineChanged: (value) {
              set.inclinePercent = value;
              onValuesChanged();
            },
            onResistanceChanged: (value) {
              set.resistanceLevel = value;
              onValuesChanged();
            },
            onPaceChanged: (value) {
              set.paceSecondsPerKm = value;
              onValuesChanged();
            },
            onToggle: () => onToggleSet(setIndex),
            onDelete: () => onRemoveSet(setIndex),
          );
        }),
        if (exercise.recordType.usesSets) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: exerciseIndex == 0
                  ? const Key('addSetButton')
                  : Key('addSetButton$exerciseIndex'),
              onPressed: onAddSet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('セットを追加'),
            ),
          ),
        ],
      ],
    );
  }
}

class WorkoutDraftSummary {
  const WorkoutDraftSummary({
    required this.date,
    required this.exerciseNames,
    required this.setCount,
  });

  final DateTime date;
  final List<String> exerciseNames;
  final int setCount;

  static WorkoutDraftSummary? tryParse(String? encoded) {
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final exercises = json['exercises'] as List<dynamic>;
      if (exercises.isEmpty) return null;
      final names = <String>[];
      final identities = <String>{};
      var sets = 0;
      for (final item in exercises) {
        final exercise = item as Map<String, dynamic>;
        final name = exercise['name'] as String?;
        if (name != null &&
            name.isNotEmpty &&
            identities.add(
              exerciseIdentity(exercise['exerciseId'] as String?, name),
            )) {
          names.add(
            exerciseDisplayName(
              name,
              exerciseId: exercise['exerciseId'] as String?,
            ),
          );
        }
        sets += (exercise['sets'] as List<dynamic>? ?? const []).length;
      }
      if (names.isEmpty) return null;
      return WorkoutDraftSummary(
        date:
            DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        exerciseNames: names,
        setCount: sets,
      );
    } catch (_) {
      return null;
    }
  }
}

String formatWeight(double weight) {
  if (weight == weight.roundToDouble()) return weight.toInt().toString();
  return weight
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double parseWeight(String? text) =>
    double.tryParse((text ?? '').replaceAll(',', '.')) ?? 0;

String formatDurationSeconds(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String formatPace(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class WorkoutSet {
  WorkoutSet({
    String? setId,
    required this.weight,
    required this.reps,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    double speedKmh = 0,
    this.inclinePercent = 0,
    this.resistanceLevel = 0,
    this.paceSecondsPerKm = 0,
    // Keep the public constructor compatible with existing callers.
    // ignore: prefer_initializing_formals
  }) : _speedKmh = speedKmh,
       setId = setId ?? _newWorkoutIdentity();

  factory WorkoutSet.nextFrom(WorkoutSet? previous) => WorkoutSet(
    weight: previous?.weight ?? 0,
    reps: previous?.reps ?? 0,
    durationSeconds: previous?.durationSeconds ?? 0,
    distanceKm: previous?.distanceKm ?? 0,
    speedKmh: previous?.speedKmh ?? 0,
    inclinePercent: previous?.inclinePercent ?? 0,
    resistanceLevel: previous?.resistanceLevel ?? 0,
    paceSecondsPerKm: previous?.paceSecondsPerKm ?? 0,
  );

  final String setId;
  double weight;
  int reps;
  int durationSeconds;
  double distanceKm;
  double _speedKmh;
  double get speedKmh => activitySpeedKmh(
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    speedKmh: _speedKmh,
    paceSecondsPerKm: paceSecondsPerKm,
  );
  set speedKmh(double value) => _speedKmh = value;
  double inclinePercent;
  double resistanceLevel;
  int paceSecondsPerKm;
  bool completed = false;
}

class RecordedSet {
  const RecordedSet({
    this.exerciseName = 'ベンチプレス',
    this.exerciseId,
    this.distanceUnit = 'km',
    this.equipment = '',
    this.bodyPart = '胸',
    this.recordType = ExerciseRecordType.weightReps,
    required this.weight,
    required this.reps,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    this.speedKmh = 0,
    this.inclinePercent = 0,
    this.resistanceLevel = 0,
    this.paceSecondsPerKm = 0,
    required this.completed,
  });

  final String exerciseName;
  final String? exerciseId;
  final String distanceUnit;
  final String equipment;
  String get identity => exerciseIdentity(exerciseId, exerciseName);
  final String bodyPart;
  final ExerciseRecordType recordType;
  final double weight;
  final int reps;
  final int durationSeconds;
  final double distanceKm;
  final double speedKmh;
  final double inclinePercent;
  final double resistanceLevel;
  final int paceSecondsPerKm;
  final bool completed;

  bool get isTreadmill =>
      exerciseId == 'treadmill' ||
      (exerciseId == null && exerciseName == 'トレッドミル');

  bool get hasRequiredValues => switch (recordType) {
    ExerciseRecordType.assistedReps =>
      weight.isFinite && weight >= 0 && reps > 0,
    ExerciseRecordType.weightReps =>
      (weight > 0 ||
              (weight == 0 &&
                  usesAdditionalWeight(
                    exerciseName,
                    exerciseId: exerciseId,
                  ))) &&
          reps > 0,
    ExerciseRecordType.bodyweightReps => reps > 0,
    ExerciseRecordType.timed => durationSeconds > 0,
    ExerciseRecordType.loadedDistance => weight >= 0 && distanceKm > 0,
    ExerciseRecordType.cardio => _hasActivityValues,
    ExerciseRecordType.distance => durationSeconds > 0 && distanceKm > 0,
  };

  bool get _hasActivityValues {
    if (isTreadmill) {
      return durationSeconds > 0 || (distanceKm.isFinite && distanceKm > 0);
    }
    if (durationSeconds <= 0) return false;
    final fields = ExerciseFormCatalog.byId[exerciseId]?.recordFields;
    if (fields != null && !fields.contains('distance')) {
      if (fields.contains('resistance') || fields.contains('speed')) {
        return resistanceLevel > 0 || speedKmh > 0;
      }
      return true; // Duration-only activities such as jump rope.
    }
    return exerciseName == 'ステアクライマー'
        ? resistanceLevel > 0 || speedKmh > 0
        : distanceKm > 0;
  }

  String get displaySummary => switch (recordType) {
    ExerciseRecordType.assistedReps =>
      '補助 ${formatWeight(weight)} kg × $reps 回',
    ExerciseRecordType.weightReps =>
      usesAdditionalWeight(exerciseName, exerciseId: exerciseId)
          ? '${weight == 0 ? '自重' : '+${formatWeight(weight)} kg'} × $reps 回'
          : '${formatWeight(weight)} kg × $reps 回',
    ExerciseRecordType.bodyweightReps => '$reps 回',
    ExerciseRecordType.timed => '${formatDurationSeconds(durationSeconds)} 保持',
    ExerciseRecordType.cardio ||
    ExerciseRecordType.distance ||
    ExerciseRecordType.loadedDistance => activitySummary,
  };

  String get activitySummary {
    final values = <String>[
      if (recordType == ExerciseRecordType.loadedDistance)
        '${formatWeight(weight)} kg',
      if (durationSeconds > 0) formatDurationSeconds(durationSeconds),
    ];
    if (distanceKm > 0) {
      values.add(
        '${formatWeight(distanceUnit == 'm' ? distanceKm * 1000 : distanceKm)} $distanceUnit',
      );
    }
    final speed = activitySpeedKmh(
      durationSeconds: durationSeconds,
      distanceKm: distanceKm,
      speedKmh: speedKmh,
      paceSecondsPerKm: paceSecondsPerKm,
    );
    if (speed > 0) values.add('${formatWeight(speed)} km/h');
    if (inclinePercent > 0) values.add('傾斜 ${formatWeight(inclinePercent)}%');
    if (resistanceLevel > 0) {
      values.add('レベル ${formatWeight(resistanceLevel)}');
    }
    return values.join(' ・ ');
  }

  factory RecordedSet.fromJson(Map<String, dynamic> json) => RecordedSet(
    exerciseName: json['exerciseName'] as String? ?? 'ベンチプレス',
    exerciseId: json['exerciseId'] as String?,
    distanceUnit: json['distanceUnit'] as String? ?? 'km',
    equipment: json['equipment'] as String? ?? '',
    bodyPart: json['bodyPart'] as String? ?? '胸',
    recordType: json['recordType'] == null
        ? (usesAssistanceWeight(
                json['exerciseName'] as String? ?? '',
                exerciseId: json['exerciseId'] as String?,
              )
              ? ExerciseRecordType.bodyweightReps
              : recordTypeForExerciseName(
                  json['exerciseName'] as String? ?? 'ベンチプレス',
                  bodyPart: json['bodyPart'] as String? ?? '胸',
                ))
        : ExerciseRecordType.fromName(json['recordType'] as String?),
    weight: (json['weight'] as num?)?.toDouble() ?? 0,
    reps: (json['reps'] as num?)?.toInt() ?? 0,
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0,
    inclinePercent: (json['inclinePercent'] as num?)?.toDouble() ?? 0,
    resistanceLevel: (json['resistanceLevel'] as num?)?.toDouble() ?? 0,
    paceSecondsPerKm: (json['paceSecondsPerKm'] as num?)?.toInt() ?? 0,
    completed: json['completed'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'exerciseName': exerciseName,
    'bodyPart': bodyPart,
    if (exerciseId != null) 'exerciseId': exerciseId,
    'distanceUnit': distanceUnit,
    if (equipment.isNotEmpty) 'equipment': equipment,
    'recordType': recordType.name,
    'weight': weight,
    'reps': reps,
    'durationSeconds': durationSeconds,
    'distanceKm': distanceKm,
    'speedKmh': speedKmh,
    'inclinePercent': inclinePercent,
    'resistanceLevel': resistanceLevel,
    'paceSecondsPerKm': paceSecondsPerKm,
    'completed': completed,
  };
}

List<SavedWorkoutTemplate> decodeWorkoutTemplates(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(SavedWorkoutTemplate.tryFromJson)
      .whereType<SavedWorkoutTemplate>()
      .toList(growable: false);
}

List<ExerciseTemplate> decodeExerciseTemplates(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(ExerciseTemplate.tryFromJson)
      .whereType<ExerciseTemplate>()
      .map(
        (e) => e.exerciseId == null ? e.withId(legacyCustomExerciseId(e)) : e,
      )
      .toList(growable: false);
}

Map<String, List<RecordedSet>> groupRecordedSets(
  Iterable<RecordedSet> sets, {
  bool preserveStoredIds = false,
}) {
  final groups = <String, List<RecordedSet>>{};
  for (final set in sets) {
    // Editing/restoring must retain each saved ID, even when history and PR
    // aggregate a confirmed alias under its canonical identity.
    final key = preserveStoredIds && set.exerciseId != null
        ? 'id:${set.exerciseId}'
        : set.identity;
    groups.putIfAbsent(key, () => []).add(set);
  }
  return groups;
}

// WorkoutPage.history can be a subset (e.g. repeat one past workout). Always
// reconcile consents against the full persisted history, never that UI subset.
Future<void> syncSavedTrainingEquipment() async {
  final prefs = await SharedPreferences.getInstance();
  await TrainingEquipmentServices.journal.reconcile(
    decodeWorkoutHistory(prefs.getString('workout_history'))
        .map(equipmentWorkoutFromRecord)
        .toList(),
  );
}

EquipmentWorkout equipmentWorkoutFromRecord(WorkoutRecord record) =>
    EquipmentWorkout(
      key: record.date.toIso8601String(),
      storeId: record.customPlaceId == null ? record.gymStoreId : null,
      completed: record.trainerWorkoutId == null,
      exercises: {
        for (final set in record.sets)
          if (set.completed &&
              set.hasRequiredValues &&
              set.exerciseId != null &&
              ExerciseFormCatalog.byId.containsKey(set.exerciseId))
            ExerciseFormCatalog.canonicalId(
              set.exerciseId!,
            ): exerciseDisplayName(
              set.exerciseName,
              exerciseId: set.exerciseId,
            ),
      },
    );

class WorkoutRecord {
  const WorkoutRecord({
    required this.date,
    required this.sets,
    this.durationSeconds = 0,
    this.gymName,
    this.gymStoreId,
    this.customPlaceId,
    this.note = '',
    this.trainerWorkoutId,
    this.trainerOwnerUserId,
  });

  final DateTime date;
  final List<RecordedSet> sets;
  final int durationSeconds;
  final String? gymName;
  final String? gymStoreId;
  final String? customPlaceId;
  final String note;

  /// Supabase workouts.id. Only records with this ID are changed by trainer sync.
  final String? trainerWorkoutId;
  final String? trainerOwnerUserId;

  Map<String, List<RecordedSet>> get exerciseGroups => groupRecordedSets(sets);
  List<String> get exerciseNames => exerciseGroups.values
      .map(
        (group) => exerciseDisplayName(
          group.first.exerciseName,
          exerciseId: group.first.exerciseId,
        ),
      )
      .toList(growable: false);

  List<String> get bodyParts =>
      sets.map((set) => set.bodyPart).toSet().toList(growable: false);

  String get durationLabel {
    if (durationSeconds <= 0) return '';
    final minutes = (durationSeconds / 60).ceil();
    return '$minutes分';
  }

  String get summaryLabel {
    final setCount = sets.where((set) => set.recordType.usesSets).length;
    final parts = <String>['${exerciseNames.length}種目'];
    if (setCount > 0) parts.add('$setCountセット');
    if (volume > 0) parts.add('${formatVolumeKg(volume)} kg');
    if (WorkoutUiPreference.workoutDurationEnabled &&
        durationLabel.isNotEmpty) {
      parts.add(durationLabel);
    }
    return parts.join(' ・ ');
  }

  double get volume => sets.fold<double>(
    0,
    (total, set) =>
        total +
        (set.recordType == ExerciseRecordType.weightReps &&
                set.bodyPart != '有酸素'
            ? set.weight * set.reps
            : 0),
  );

  RecordedSet get bestSet => sets.reduce(
    (best, set) => set.weight * set.reps > best.weight * best.reps ? set : best,
  );

  RecordedSet get highlightSet {
    final weighted = sets
        .where((set) => set.recordType == ExerciseRecordType.weightReps)
        .toList();
    if (weighted.isEmpty) return sets.first;
    return weighted.reduce(
      (best, set) =>
          set.weight * set.reps > best.weight * best.reps ? set : best,
    );
  }

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    date: DateTime.parse(json['date'] as String),
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    gymName: json['gymName'] as String?,
    gymStoreId: json['gymStoreId'] as String?,
    customPlaceId: json['customPlaceId'] as String?,
    note: json['note'] as String? ?? '',
    trainerWorkoutId: json['trainerWorkoutId'] as String?,
    trainerOwnerUserId: json['trainerOwnerUserId'] as String?,
    sets: (json['sets'] as List<dynamic>)
        .map((item) => RecordedSet.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  static WorkoutRecord? tryFromJson(Object? source) {
    if (source is! Map<String, dynamic>) return null;
    try {
      final workout = WorkoutRecord.fromJson(source);
      return workout.sets.isEmpty ? null : workout;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'durationSeconds': durationSeconds,
    'gymName': gymName,
    if (gymStoreId != null) 'gymStoreId': gymStoreId,
    if (customPlaceId != null) 'customPlaceId': customPlaceId,
    'note': note,
    if (trainerWorkoutId != null) 'trainerWorkoutId': trainerWorkoutId,
    if (trainerOwnerUserId != null) 'trainerOwnerUserId': trainerOwnerUserId,
    'sets': sets.map((set) => set.toJson()).toList(),
  };
}

/// Fetch every page before changing local history. A failed page never causes
/// a partial import or removal of an existing record.
Future<List<Map<String, dynamic>>> fetchAllTrainerWorkouts(
  Future<List<Map<String, dynamic>>> Function(int offset) fetchPage,
) async {
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0; ; offset += 100) {
    final page = await fetchPage(offset);
    rows.addAll(page);
    if (page.length < 100) return rows;
  }
}

/// Apply only server-identified trainer records. Self and backup records are
/// never removed by absence from a server response.
List<WorkoutRecord> reconcileTrainerWorkouts(
  List<WorkoutRecord> history,
  List<Map<String, dynamic>> rows,
  String userId,
) {
  final updated = List<WorkoutRecord>.from(history);
  final seen = <String>{};
  for (final row in rows) {
    final id = row['id'];
    if (id is! String || id.isEmpty || !seen.add(id)) {
      throw const FormatException('Invalid trainer workout ID');
    }
    final matching = updated.indexWhere(
      (w) => w.trainerWorkoutId == id && w.trainerOwnerUserId == userId,
    );
    if (row['canceled_at'] != null) {
      if (matching >= 0) updated.removeAt(matching);
      continue;
    }
    final incoming = WorkoutRecord.fromJson({
      'date': row['performed_at'],
      'durationSeconds': row['duration_seconds'],
      'gymName': row['gym_name'],
      'note': row['note'],
      'sets': row['sets'],
      'trainerWorkoutId': id,
      'trainerOwnerUserId': userId,
    });
    if (incoming.sets.isEmpty) {
      throw const FormatException('Trainer workout has no sets');
    }
    final canceled = row['canceled_at'] != null;
    if (matching >= 0) {
      if (canceled) {
        updated.removeAt(matching);
      } else {
        updated[matching] = incoming;
      }
      continue;
    }
    // Old manual receipts had no provenance. Even an exact payload could be a
    // self record, so suppress a duplicate without tagging or deleting it.
    final legacyMatches = <int>[];
    for (var i = 0; i < updated.length; i++) {
      final local = updated[i];
      if (local.trainerWorkoutId == null &&
          local.note.isEmpty &&
          local.gymStoreId == null &&
          local.customPlaceId == null &&
          local.date.toUtc() == incoming.date.toUtc() &&
          local.durationSeconds == incoming.durationSeconds &&
          local.gymName == incoming.gymName &&
          jsonEncode(local.sets.map((s) => s.toJson()).toList()) ==
              jsonEncode(incoming.sets.map((s) => s.toJson()).toList())) {
        legacyMatches.add(i);
      }
    }
    if (legacyMatches.length == 1) continue;
    if (!canceled) {
      updated.add(incoming);
    }
  }
  return sortWorkoutsNewestFirst(updated);
}

List<WorkoutRecord> decodeWorkoutItems(Object? source) {
  if (source is! List<dynamic>) return [];
  return source
      .map(WorkoutRecord.tryFromJson)
      .whereType<WorkoutRecord>()
      .toList(growable: false);
}

List<WorkoutRecord> decodeWorkoutHistory(String? encoded) {
  if (encoded == null) return [];
  try {
    return decodeWorkoutItems(jsonDecode(encoded));
  } catch (_) {
    return [];
  }
}

List<WorkoutRecord> sortWorkoutsNewestFirst(Iterable<WorkoutRecord> workouts) =>
    workouts.toList()..sort((a, b) => b.date.compareTo(a.date));

List<RecordedSet> latestSetsForExercise(
  Iterable<WorkoutRecord> workouts,
  String exerciseName, {
  String? exerciseId,
}) {
  final identity = exerciseIdentity(exerciseId, exerciseName);
  WorkoutRecord? latest;
  for (final workout in workouts) {
    if (!workout.sets.any((set) => set.identity == identity)) continue;
    if (latest == null || workout.date.isAfter(latest.date)) latest = workout;
  }
  if (latest == null) return [];
  return latest.sets
      .where((set) => set.identity == identity)
      .toList(growable: false);
}

const setLabelStyle = TextStyle(
  fontSize: 10,
  color: Color(0xFF777F78),
  fontWeight: FontWeight.w800,
  letterSpacing: 1,
);

class SetHeader extends StatelessWidget {
  const SetHeader({
    super.key,
    required this.recordType,
    this.showCompletionCheck = true,
    this.trailingWidth,
  });

  final ExerciseRecordType recordType;
  final bool showCompletionCheck;
  final double? trailingWidth;

  @override
  Widget build(BuildContext context) {
    if (!recordType.usesSets) return const SizedBox.shrink();
    final labels = switch (recordType) {
      ExerciseRecordType.weightReps => const ['KG', 'REPS'],
      ExerciseRecordType.assistedReps => const ['補助 KG', 'REPS'],
      ExerciseRecordType.bodyweightReps => const ['REPS'],
      ExerciseRecordType.timed => const ['TIME'],
      _ => const <String>[],
    };
    return Row(
      children: [
        const SizedBox(width: 28, child: Text('SET', style: setLabelStyle)),
        for (final (index, label) in labels.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Center(child: Text(label, style: setLabelStyle)),
          ),
        ],
        SizedBox(width: trailingWidth ?? (showCompletionCheck ? 96 : 52)),
      ],
    );
  }
}

class WorkoutSetRowLayout extends StatelessWidget {
  const WorkoutSetRowLayout({
    super.key,
    required this.number,
    required this.values,
    this.trailing = const [],
  });

  final int number;
  final List<Widget> values;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$number',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        for (final (index, value) in values.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(child: value),
        ],
        const SizedBox(width: 8),
        ...trailing,
      ],
    ),
  );
}

class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.number,
    this.fieldPrefix = '',
    required this.set,
    required this.recordType,
    required this.exerciseName,
    this.exerciseId,
    this.distanceUnit = 'km',
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onDurationChanged,
    required this.onDistanceChanged,
    required this.onSpeedChanged,
    required this.onInclineChanged,
    required this.onResistanceChanged,
    required this.onPaceChanged,
    required this.onToggle,
    required this.onDelete,
    this.showCompletionCheck = true,
    this.weightFocus,
    this.repsFocus,
    this.nextWeight,
    this.nextReps,
  });

  final FocusNode? weightFocus, repsFocus;
  final VoidCallback? nextWeight, nextReps;
  final int number;
  final String fieldPrefix;
  final WorkoutSet set;
  final ExerciseRecordType recordType;
  final String exerciseName;
  final String? exerciseId;
  final String distanceUnit;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDistanceChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onInclineChanged;
  final ValueChanged<double> onResistanceChanged;
  final ValueChanged<int> onPaceChanged;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool showCompletionCheck;

  @override
  Widget build(BuildContext context) {
    if (!recordType.usesSets) {
      return _ActivityInputGrid(
        fieldPrefix: fieldPrefix,
        exerciseName: exerciseName,
        exerciseId: exerciseId,
        distanceUnit: distanceUnit,
        onWeightChanged: onWeightChanged,
        recordType: recordType,
        set: set,
        onDurationChanged: onDurationChanged,
        onDistanceChanged: onDistanceChanged,
        onSpeedChanged: onSpeedChanged,
        onInclineChanged: onInclineChanged,
        onResistanceChanged: onResistanceChanged,
        onPaceChanged: onPaceChanged,
      );
    }
    return WorkoutSetRowLayout(
      number: number,
      values: [
        if (recordType.hasWeightInput) ...[
          ValueBox(
            largeTouchTarget: true,
            key: Key('weightField$fieldPrefix$number'),
            value: set.weight,
            stepLabel: recordType == ExerciseRecordType.assistedReps
                ? '補助 KG'
                : 'KG',
            focusNode: weightFocus,
            onNext: nextWeight,
            normalizeZeros: true,
            allowDecimal: true,
            onChanged: (value) => onWeightChanged(value.toDouble()),
          ),
        ],
        if (recordType.hasWeightInput ||
            recordType == ExerciseRecordType.bodyweightReps)
          ValueBox(
            largeTouchTarget: true,
            key: Key('repsField$fieldPrefix$number'),
            value: set.reps,
            stepLabel: 'REPS',
            focusNode: repsFocus,
            onNext: nextReps,
            normalizeZeros: true,
            onChanged: (value) => onRepsChanged(value.toInt()),
          ),
        if (recordType == ExerciseRecordType.timed)
          ValueBox(
            largeTouchTarget: true,
            key: Key('durationField$fieldPrefix$number'),
            value: set.durationSeconds,
            onChanged: (value) => onDurationChanged(value.toInt()),
          ),
      ],
      trailing: [
        if (showCompletionCheck) ...[
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton.filled(
              key: Key('toggleSet$fieldPrefix$number'),
              padding: EdgeInsets.zero,
              onPressed: onToggle,
              style: IconButton.styleFrom(
                backgroundColor: set.completed
                    ? FamilyPalette.of(context).accent
                    : const Color(0xFFE8EBE5),
                foregroundColor: const Color(0xFF101820),
              ),
              icon: Icon(
                set.completed ? Icons.check_rounded : Icons.circle_outlined,
                size: 18,
              ),
            ),
          ),
        ],
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: Key('deleteSet$fieldPrefix$number'),
            tooltip: 'セットを削除',
            padding: EdgeInsets.zero,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ),
      ],
    );
  }
}

class _ActivityInputGrid extends StatelessWidget {
  const _ActivityInputGrid({
    required this.fieldPrefix,
    required this.exerciseName,
    this.exerciseId,
    this.distanceUnit = 'km',
    required this.recordType,
    required this.set,
    required this.onWeightChanged,
    required this.onDurationChanged,
    required this.onDistanceChanged,
    required this.onSpeedChanged,
    required this.onInclineChanged,
    required this.onResistanceChanged,
    required this.onPaceChanged,
  });

  final String fieldPrefix;
  final String exerciseName;
  final String? exerciseId;
  final String distanceUnit;
  final ExerciseRecordType recordType;
  final WorkoutSet set;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDistanceChanged;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onInclineChanged;
  final ValueChanged<double> onResistanceChanged;
  final ValueChanged<int> onPaceChanged;

  @override
  Widget build(BuildContext context) => StatefulBuilder(
    builder: (context, update) {
      final fields = ExerciseFormCatalog.byId[exerciseId]?.recordFields;
      final showDistance =
          fields?.contains('distance') ?? (exerciseName != 'ステアクライマー');
      final showSpeed =
          showDistance ||
          (fields?.contains('speed') ?? exerciseName == 'ステアクライマー');
      final automaticSpeed =
          set.durationSeconds > 0 &&
          set.distanceKm.isFinite &&
          set.distanceKm > 0;
      final showIncline =
          fields?.contains('incline') ?? (exerciseName == 'トレッドミル');
      final showResistance =
          fields?.contains('resistance') ??
          (exerciseName == 'エアロバイク' ||
              exerciseName == 'クロストレーナー' ||
              exerciseName == 'ステアクライマー');
      final isTreadmill =
          exerciseId == 'treadmill' ||
          (exerciseId == null && exerciseName == 'トレッドミル');
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (recordType == ExerciseRecordType.loadedDistance)
            _MetricInput(
              key: Key('loadedWeightField$fieldPrefix'),
              label: '重量（kg）',
              value: set.weight,
              onChanged: onWeightChanged,
            ),
          _MetricInput(
            key: Key('durationField$fieldPrefix'),
            label: '時間（分）',
            value: set.durationSeconds / 60,
            onChanged: (value) =>
                update(() => onDurationChanged((value * 60).round())),
          ),
          if (showDistance)
            _MetricInput(
              key: Key('distanceField$fieldPrefix'),
              label: '距離（$distanceUnit）',
              value: distanceUnit == 'm'
                  ? set.distanceKm * 1000
                  : set.distanceKm,
              onChanged: (value) => update(
                () => onDistanceChanged(
                  distanceUnit == 'm' ? value / 1000 : value,
                ),
              ),
            ),
          if (showSpeed)
            _MetricInput(
              key: Key('speedField$fieldPrefix'),
              label: automaticSpeed ? '平均速度（km/h・自動）' : '速度（km/h・任意）',
              readOnly: automaticSpeed,
              value: set.speedKmh,
              onChanged: onSpeedChanged,
            ),
          if (showIncline)
            _MetricInput(
              key: Key('inclineField$fieldPrefix'),
              label: isTreadmill ? '傾斜（%・任意）' : '傾斜（%）',
              value: set.inclinePercent,
              onChanged: onInclineChanged,
            ),
          if (showResistance)
            _MetricInput(
              key: Key('resistanceField$fieldPrefix'),
              label: '負荷レベル',
              value: set.resistanceLevel,
              onChanged: onResistanceChanged,
            ),
        ],
      );
    },
  );
}

class _MetricInput extends StatelessWidget {
  const _MetricInput({
    this.readOnly = false,
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool readOnly;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: setLabelStyle),
          const SizedBox(height: 4),
          if (readOnly)
            InputDecorator(
              decoration: const InputDecoration(),
              child: Text(formatWeight(value)),
            )
          else
            ValueBox(
              value: value,
              allowDecimal: true,
              onChanged: (next) => onChanged(next.toDouble()),
            ),
        ],
      ),
    );
  }
}

/// Normalize only the integer prefix, keeping selection relative to removed digits.
class NumericLeadingZeroFormatter extends TextInputFormatter {
  const NumericLeadingZeroFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final match = RegExp(r'^0+(?=\d)').firstMatch(newValue.text);
    if (match == null) return newValue;
    final removed = match.end;
    int offset(int value) => value < 0
        ? value
        : (value - removed).clamp(0, newValue.text.length - removed);
    return newValue.copyWith(
      text: newValue.text.substring(removed),
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}

/// Accept decimal separators supplied by Android IMEs without dropping them.
class DecimalNumberInputFormatter extends TextInputFormatter {
  const DecimalNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final normalized = newValue.text.replaceAll(RegExp(r'[,．。٫]'), '.');
    if (!RegExp(r'^\d*(\.\d{0,2})?$').hasMatch(normalized)) {
      return oldValue;
    }
    return newValue.copyWith(text: normalized);
  }
}

/// Shared SK/TRAINER numeric input behavior for ExerciseInputCard.
class WorkoutNumericInputController {
  WorkoutNumericInputController(this.exercises);

  final List<WorkoutExercise> Function() exercises;
  final _numericFocus = <WorkoutSet, List<FocusNode>>{};
  late final _pad = _NumericPadController(() => _numericOrder);

  List<FocusNode> nodesFor(WorkoutSet set) =>
      _numericFocus.putIfAbsent(set, () => [FocusNode(), FocusNode()]);

  List<FocusNode> get _numericOrder => [
    for (final exercise in exercises())
      for (final set in exercise.sets) ...[
        if (exercise.recordType.hasWeightInput) nodesFor(set)[0],
        if (exercise.recordType.hasWeightInput ||
            exercise.recordType == ExerciseRecordType.bodyweightReps)
          nodesFor(set)[1],
      ],
  ];

  VoidCallback? nextNumeric(FocusNode node) {
    final order = _numericOrder;
    final index = order.indexOf(node);
    if (index < 0 || index == order.length - 1) return null;
    return () {
      final current = _numericOrder;
      final index = current.indexOf(node);
      if (index < 0 || index + 1 >= current.length) return;
      final next = current[index + 1];
      next.requestFocus();
      if (next.context != null) {
        Scrollable.ensureVisible(next.context!, alignment: 0.35);
      }
    };
  }

  bool get isActive => _pad.active != null;
  Widget get keypad => _WorkoutNumericKeypad(controller: _pad);
  Widget wrap(Widget child) => _NumericPadScope(controller: _pad, child: child);

  void dispose() {
    _pad.dispose();
    for (final nodes in _numericFocus.values) {
      for (final node in nodes) {
        node.dispose();
      }
    }
  }
}

class _NumericPadScope extends InheritedWidget {
  const _NumericPadScope({required this.controller, required super.child});
  final _NumericPadController controller;
  @override
  bool updateShouldNotify(_NumericPadScope oldWidget) =>
      controller != oldWidget.controller;
}

class _NumericPadController extends ChangeNotifier {
  _NumericPadController(this.order);
  final List<FocusNode> Function() order;
  _ValueBoxState? active;
  bool _disposed = false;
  bool _queued = false;
  bool _reveal = false;
  void _refresh({bool reveal = false}) {
    if (_disposed) return;
    _reveal = _reveal || reveal;
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (_disposed) return;
      notifyListeners();
      final shouldReveal = _reveal;
      _reveal = false;
      if (shouldReveal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = active;
          if (!_disposed && target != null && target.mounted) {
            Scrollable.ensureVisible(target.context, alignment: 0.4);
          }
        });
      }
    });
  }

  void activate(_ValueBoxState field) {
    if (_disposed) return;
    active = field;
    _refresh(reveal: true);
  }

  void deactivate(_ValueBoxState field) {
    if (active != field) return;
    active = null;
    _refresh();
  }

  void move(int direction) {
    final field = active;
    if (field == null || !field.mounted) return;
    final nodes = order();
    final index = nodes.indexOf(field._focus);
    final next = index + direction;
    if (index >= 0 && next >= 0 && next < nodes.length) {
      nodes[next].requestFocus();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    active = null;
    super.dispose();
  }
}

class _WorkoutNumericKeypad extends StatelessWidget {
  const _WorkoutNumericKeypad({required this.controller});
  final _NumericPadController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final field = controller.active;
      if (field == null || !field.mounted) return const SizedBox.shrink();
      final order = controller.order();
      final index = order.indexOf(field._focus);
      final last = index == order.length - 1;
      Widget key(
        String text,
        String id,
        VoidCallback? action, {
        bool accent = false,
        bool secondary = false,
      }) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: SizedBox(
            height: 46,
            child: TextButton(
              key: Key('numericKey$id'),
              onPressed: action,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: accent
                    ? const Color(0xFFB32635)
                    : secondary
                    ? const Color(0xFFCDD6E0)
                    : Colors.white,
                disabledBackgroundColor: secondary
                    ? const Color(0xFFDCE2E8)
                    : Colors.white,
                foregroundColor: accent
                    ? Colors.white
                    : const Color(0xFF101820),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(text),
            ),
          ),
        ),
      );
      Widget digit(String value) => key(
        value == 'delete' ? '⌫' : value,
        value,
        value == '.' && !field.widget.allowDecimal
            ? null
            : () => field._edit(value),
      );
      return TextFieldTapRegion(
        child: Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          child: Material(
            color: const Color(0xFFE8EBE5),
            child: SafeArea(
              top: false,
              child: Padding(
                key: const Key('workoutNumericKeypad'),
                padding: const EdgeInsets.fromLTRB(7, 0, 7, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${field.widget.stepLabel} 入力中',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('closeNumericKeypad'),
                            padding: EdgeInsets.zero,
                            tooltip: 'キーパッドを閉じる',
                            onPressed: () => field._focus.unfocus(),
                            icon: const Icon(
                              Icons.keyboard_hide_outlined,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              for (final row in [
                                ['1', '2', '3'],
                                ['4', '5', '6'],
                                ['7', '8', '9'],
                                ['.', '0', 'delete'],
                              ])
                                Row(children: row.map(digit).toList()),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              for (final step in [1, 5])
                                Row(
                                  children: [
                                    key(
                                      '−$step',
                                      'minus$step',
                                      () => field._step(-step),
                                      secondary: true,
                                    ),
                                    key(
                                      '+$step',
                                      'plus$step',
                                      () => field._step(step),
                                      secondary: true,
                                    ),
                                  ],
                                ),
                              Row(
                                children: [
                                  key(
                                    '前へ',
                                    'previous',
                                    index > 0
                                        ? () => controller.move(-1)
                                        : null,
                                    secondary: true,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  key(
                                    last ? '完了' : '次へ',
                                    'next',
                                    last
                                        ? () => field._focus.unfocus()
                                        : () => controller.move(1),
                                    accent: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ValueBox extends StatefulWidget {
  const ValueBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = false,
    this.largeTouchTarget = false,
    this.normalizeZeros = false,
    this.stepLabel,
    this.focusNode,
    this.onNext,
  });

  final num value;
  final bool largeTouchTarget;
  final ValueChanged<num> onChanged;
  final bool allowDecimal;
  final bool normalizeZeros;
  final String? stepLabel;
  final FocusNode? focusNode;
  final VoidCallback? onNext;

  @override
  State<ValueBox> createState() => _ValueBoxState();
}

class _ValueBoxState extends State<ValueBox> {
  late final TextEditingController _controller = TextEditingController(
    text: _text,
  );
  String get _text => widget.allowDecimal
      ? formatWeight(widget.value.toDouble())
      : '${widget.value}';

  _NumericPadController? _pad;
  late final FocusNode _localFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _localFocus;
  bool get _usesPad => widget.stepLabel != null && _pad != null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pad = context
        .dependOnInheritedWidgetOfExactType<_NumericPadScope>()
        ?.controller;
  }

  void _focusChanged() {
    if (_usesPad) {
      if (_focus.hasFocus) {
        _pad!.activate(this);
      } else {
        _pad!.deactivate(this);
      }
    }
    if (mounted) setState(() {});
  }

  void _edit(String key) {
    final old = _controller.value;
    final selection = old.selection.isValid
        ? old.selection
        : TextSelection.collapsed(offset: old.text.length);
    var start = selection.start;
    final end = selection.end;
    var insert = key;
    if (key == 'delete') {
      insert = '';
      if (start == end && start > 0) start--;
    } else if (key == '.') {
      if (!widget.allowDecimal) return;
      if (start == 0) insert = '0.';
    }
    final text = old.text.replaceRange(start, end, insert);
    if (!(widget.allowDecimal
            ? RegExp(r'^\d*([.,]\d{0,2})?$')
            : RegExp(r'^\d*$'))
        .hasMatch(text)) {
      return;
    }
    final next = const NumericLeadingZeroFormatter().formatEditUpdate(
      old,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + insert.length),
      ),
    );
    _controller.value = next;
    widget.onChanged(
      widget.allowDecimal
          ? parseWeight(next.text)
          : int.tryParse(next.text) ?? 0,
    );
  }

  @override
  void didUpdateWidget(ValueBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _localFocus).removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (oldWidget.value != widget.value &&
        parseWeight(_controller.text) != widget.value) {
      _controller.value = TextEditingValue(
        text: _text,
        selection: TextSelection.collapsed(offset: _text.length),
      );
    }
  }

  @override
  void dispose() {
    _pad?.deactivate(this);
    _focus.removeListener(_focusChanged);
    _localFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final current = widget.allowDecimal
        ? parseWeight(_controller.text)
        : int.tryParse(_controller.text) ?? 0;
    final next = (current + delta).clamp(0, double.maxFinite);
    final text = widget.allowDecimal
        ? formatWeight(next.toDouble())
        : '${next.toInt()}';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final input = TextFormField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: _usesPad
          ? TextInputType.none
          : TextInputType.numberWithOptions(decimal: widget.allowDecimal),
      onTap: () {
        if (_usesPad) _pad!.activate(this);
      },
      textInputAction: widget.onNext == null
          ? TextInputAction.done
          : TextInputAction.next,
      onEditingComplete: () {
        if (widget.onNext != null) {
          widget.onNext!();
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      textAlign: TextAlign.center,
      inputFormatters: [
        if (widget.allowDecimal)
          const DecimalNumberInputFormatter()
        else
          FilteringTextInputFormatter.digitsOnly,
        if (widget.normalizeZeros) const NumericLeadingZeroFormatter(),
      ],
      onChanged: (text) {
        final parsed = widget.allowDecimal
            ? parseWeight(text)
            : int.tryParse(text) ?? 0;
        widget.onChanged(parsed);
      },
      onSaved: (text) => widget.onChanged(
        widget.allowDecimal ? parseWeight(text) : int.tryParse(text ?? '') ?? 0,
      ),
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: widget.largeTouchTarget ? 18 : null,
      ),
      decoration: InputDecoration(
        constraints: widget.largeTouchTarget
            ? const BoxConstraints(minHeight: 48)
            : null,
        isDense: true,
        filled: true,
        fillColor: _usesPad && _focus.hasFocus
            ? const Color(0xFFFFE9E9)
            : const Color(0xFFF4F5F0),
        focusedBorder: _usesPad
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(
                  color: Color(0xFFB32635),
                  width: 2,
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
      ),
    );
    return input;
  }
}

Future<String?> showGymPicker(
  BuildContext context,
  String? currentGym, {
  String? currentStoreId,
  String? currentCustomPlaceId,
  ValueChanged<GymStore>? onStoreSelected,
  ValueChanged<TrainingPlace>? onPlaceSelected,
}) async {
  final place = await showModalBottomSheet<TrainingPlace>(
    context: context,
    showDragHandle: true,
    builder: (_) => TrainingPlacePicker(
      currentName: currentGym,
      currentStoreId: currentStoreId,
      currentCustomPlaceId: currentCustomPlaceId,
    ),
  );
  if (place?.store != null) onStoreSelected?.call(place!.store!);
  if (place != null) onPlaceSelected?.call(place);
  return place?.name;
}

class CustomGymManagementPage extends StatefulWidget {
  const CustomGymManagementPage({
    super.key,
    required this.selectedGym,
    required this.onSelectedGymChanged,
  });

  final String? selectedGym;
  final Future<void> Function(String?) onSelectedGymChanged;

  @override
  State<CustomGymManagementPage> createState() =>
      _CustomGymManagementPageState();
}

class _CustomGymManagementPageState extends State<CustomGymManagementPage> {
  late String? _selectedGym;

  @override
  void initState() {
    super.initState();
    _selectedGym = widget.selectedGym;
  }

  Future<void> _notifyChanged() => widget.onSelectedGymChanged(_selectedGym);

  Future<void> _select(String gym) async {
    if (_selectedGym == gym) return;
    setState(() => _selectedGym = gym);
    await _notifyChanged();
  }

  Future<void> _add() async {
    final name = await addCustomGym(context);
    if (!mounted || name == null) return;
    setState(() {});
    await _notifyChanged();
  }

  Future<void> _edit(String originalName) async {
    final name = await showCustomGymDialog(context, initialName: originalName);
    if (name == null || name == originalName) return;
    final updated = await CustomGymPreference.update(originalName, name);
    if (!updated || !mounted) return;
    if (_selectedGym == originalName) _selectedGym = name;
    setState(() {});
    await _notifyChanged();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('「$name」に名前を変更しました')));
    }
  }

  Future<void> _delete(String name) async {
    final index = CustomGymPreference.gyms.indexOf(name);
    final wasSelected = _selectedGym == name;
    final messenger = ScaffoldMessenger.of(context);
    await CustomGymPreference.remove(name);
    if (wasSelected) _selectedGym = null;
    if (!mounted) return;
    setState(() {});
    await _notifyChanged();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「$name」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              final restored = List<String>.from(CustomGymPreference.gyms);
              restored.insert(index.clamp(0, restored.length), name);
              await CustomGymPreference.replaceAll(restored);
              if (wasSelected) _selectedGym = name;
              if (!mounted) return;
              setState(() {});
              await _notifyChanged();
              messenger.showSnackBar(
                SnackBar(content: Text('「$name」を元に戻しました')),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final gyms = CustomGymPreference.gyms;
    final selectableGyms = [
      ...standardGyms,
      ...gyms,
      if (_selectedGym != null &&
          !standardGyms.contains(_selectedGym) &&
          !gyms.contains(_selectedGym))
        _selectedGym!,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('いつもの場所'),
        actions: [
          IconButton(
            key: const Key('addCustomGymButton'),
            tooltip: '場所を追加',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text(
            '普段使う場所を選択できます。自宅や独自のジムなどは右上の＋から追加してください。',
            style: TextStyle(color: Color(0xFF6F776F)),
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < selectableGyms.length; index++) ...[
                  ListTile(
                    key: Key('preferredGym${selectableGyms[index]}'),
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      selectableGyms[index],
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (gyms.contains(selectableGyms[index])) ...[
                          PopupMenuButton<String>(
                            key: Key('gymActions${selectableGyms[index]}'),
                            tooltip: '${selectableGyms[index]}を管理',
                            onSelected: (action) {
                              if (action == 'edit') {
                                _edit(selectableGyms[index]);
                              } else if (action == 'delete') {
                                _delete(selectableGyms[index]);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('名前を変更'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('削除')),
                            ],
                          ),
                        ],
                        Icon(
                          _selectedGym == selectableGyms[index]
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: _selectedGym == selectableGyms[index]
                              ? AppColors.primaryGreenStrong
                              : null,
                        ),
                      ],
                    ),
                    onTap: () => _select(selectableGyms[index]),
                  ),
                  if (index < selectableGyms.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BackupDataManagementPage extends StatelessWidget {
  const BackupDataManagementPage({
    super.key,
    required this.onExport,
    required this.onImportFile,
    this.onCloudSync,
    this.historyCount = 0,
  });

  final Future<void> Function(BuildContext) onExport;
  final Future<void> Function(BuildContext) onImportFile;
  final Future<int> Function()? onCloudSync;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('バックアップ・データ管理')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('exportBackupFile'),
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('バックアップを書き出す'),
                  subtitle: const Text('トレーニングデータをファイルに保存・共有'),
                  onTap: () => onExport(context),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('importBackupFile'),
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('バックアップから復元'),
                  subtitle: const Text('バックアップファイルからデータを復元'),
                  onTap: () => onImportFile(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CloudBackupSection(
            premium: SupabaseSyncService.canUseCloud,
            onOpen: onCloudSync == null || !SupabaseConfig.initialized
                ? null
                : () {
                    SupabaseSyncService.requirePremium();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CloudAccountPage(
                          historyCount: historyCount,
                          onSyncRequested: onCloudSync!,
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

/// Only this area is locked; local file actions stay available above it.
class CloudBackupSection extends StatelessWidget {
  const CloudBackupSection({super.key, required this.premium, this.onOpen});
  final bool premium;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('cloudBackupSection'),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'クラウドバックアップ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (!premium) const Icon(Icons.lock_outline, size: 18),
              const Text(' Premium'),
            ],
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: premium ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('クラウドにトレーニング記録をバックアップ・復元'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('cloudBackupButton'),
                  onPressed: premium ? onOpen : null,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('クラウドを開く'),
                ),
              ],
            ),
          ),
          if (!premium)
            const Text('Premium限定・現在準備中', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

class _ProfileNameCard extends StatefulWidget {
  const _ProfileNameCard({super.key});

  @override
  State<_ProfileNameCard> createState() => _ProfileNameCardState();
}

class _ProfileNameCardState extends State<_ProfileNameCard> {
  String _name = '';
  String? _avatarPath;
  bool _avatarAvailable = false;
  bool _loaded = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final name = await ProfilePreference.load();
      if (!mounted) return;
      setState(() {
        _name = name;
        _loaded = true;
      });
      final repo = configuredFriends();
      final owner = repo?.userId;
      final profile = await repo?.profile();
      if (mounted &&
          (repo == null || repo.client.auth.currentUser?.id == owner)) {
        setState(() {
          final cloudName = profile?['display_name'] as String?;
          if (cloudName != null) _name = cloudName;
          _avatarPath = profile?['avatar_path'] as String?;
          _avatarAvailable = profile?.containsKey('avatar_path') ?? false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _edit() async {
    if (_editing || !_loaded) return;
    setState(() => _editing = true);
    final repo = configuredFriends();
    final owner = repo?.userId;
    void checkAccount() {
      if (repo != null && repo.client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
    }

    final saver = ProfileEditSaveCoordinator(
      checkAccount: checkAccount,
      saveLocalName: ProfilePreference.setDisplayName,
      saveRemote: repo == null
          ? null
          : (name, photoChanged, photo) async {
              checkAccount();
              if (photoChanged) {
                await repo.setAvatar(
                  photo,
                  expectedOwner: owner,
                  displayName: name,
                );
              } else {
                await repo.ensureProfile(name);
              }
            },
    );
    try {
      await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProfileEditDialog(
          initialName: _name,
          currentAvatar: FriendAvatar(
            repository: repo,
            path: _avatarPath,
            radius: 40,
          ),
          hasPhoto: _avatarPath != null,
          canEditPhoto: repo != null && _avatarAvailable,
          saver: saver,
          pickPhoto: () async {
            checkAccount();
            final picked = await image_picker.ImagePicker().pickImage(
              source: image_picker.ImageSource.gallery,
              maxWidth: 1024,
              maxHeight: 1024,
            );
            if (picked == null) return null;
            final photo = await prepareFriendAvatar(await picked.readAsBytes());
            checkAccount();
            return photo;
          },
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Row(
        children: [
          InkWell(
            key: const Key('editProfileAvatar'),
            borderRadius: BorderRadius.circular(28),
            onTap: _loaded && !_editing ? _edit : null,
            child: Tooltip(
              message: 'プロフィールを編集',
              child: FriendAvatar(
                repository: configuredFriends(),
                path: _avatarPath,
                radius: 28,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name.isEmpty ? ProfilePreference.defaultDisplayName : _name,
                  key: const Key('profileDisplayName'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '今日の1セットを積み上げよう',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFF777F78)),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('editProfileDisplayName'),
            tooltip: 'プロフィールを編集',
            onPressed: _loaded && !_editing ? _edit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    this.onTrainerLinked,
    required this.selectedGym,
    required this.history,
    required this.onSyncRequested,
    required this.workoutTemplates,
    required this.bodyWeights,
    required this.onBackupImported,
    required this.restTimerEnabled,
    required this.restTimerSeconds,
    required this.completionCheckEnabled,
    required this.workoutTimerEnabled,
    required this.workoutDurationEnabled,
    required this.onRestTimerEnabledChanged,
    required this.onRestTimerSecondsChanged,
    required this.onCompletionCheckEnabledChanged,
    required this.onWorkoutTimerEnabledChanged,
    required this.onWorkoutDurationEnabledChanged,
    required this.onCustomExercisesChanged,
    required this.onWorkoutTemplatesChanged,
    required this.onSelectedGymChanged,
  });

  final Future<void> Function()? onTrainerLinked;
  final String? selectedGym;
  final List<WorkoutRecord> history;
  final Future<int> Function() onSyncRequested;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final List<BodyWeightEntry> bodyWeights;
  final Future<int> Function(SetkeepBackup) onBackupImported;
  final bool restTimerEnabled;
  final int restTimerSeconds;
  final bool completionCheckEnabled;
  final bool workoutTimerEnabled;
  final bool workoutDurationEnabled;
  final ValueChanged<bool> onRestTimerEnabledChanged;
  final ValueChanged<int> onRestTimerSecondsChanged;
  final ValueChanged<bool> onCompletionCheckEnabledChanged;
  final ValueChanged<bool> onWorkoutTimerEnabledChanged;
  final ValueChanged<bool> onWorkoutDurationEnabledChanged;
  final VoidCallback onCustomExercisesChanged;
  final Future<void> Function(List<SavedWorkoutTemplate>)
  onWorkoutTemplatesChanged;
  final Future<void> Function(String?) onSelectedGymChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          const Text(
            'マイページ',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 22),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                _ProfileNameCard(key: ValueKey(configuredFriends()?.userId)),
                const Divider(height: 1, thickness: 0.5),
                ListTile(
                  key: const Key('accountButton'),
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('アカウント'),
                  subtitle: const Text('メールで登録・ログイン'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CloudAccountPage(
                        historyCount: history.length,
                        onSyncRequested: onSyncRequested,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle('トレーニング設定'),
          _trainingSettingsCard(context),
          _sectionTitle('利用場所'),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ListTile(
              key: const Key('registeredGymsButton'),
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('利用場所'),
              subtitle: const Text('自宅・登録店舗・いつもの場所を設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisteredGymsPage()),
                );
                final place = await TrainingPlacePreference.load();
                if (context.mounted) await onSelectedGymChanged(place.name);
              },
            ),
          ),
          _sectionTitle('SETKEEP TRAINER連携'),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ListTile(
              key: const Key('trainerQrButton'),
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('SETKEEP TRAINERと連携'),
              subtitle: Text(
                trainerPublicAccessEnabled
                    ? (Localizations.localeOf(context).languageCode == 'en'
                          ? 'Invitations, shared records and automatic sync'
                          : '招待の承認・記録の共有・代理記録の自動同期')
                    : (Localizations.localeOf(context).languageCode == 'en'
                          ? 'Coming soon'
                          : '準備中'),
              ),
              trailing: trainerPublicAccessEnabled
                  ? const Icon(Icons.chevron_right_rounded)
                  : const Icon(Icons.info_outline_rounded),
              onTap: trainerPublicAccessEnabled
                  ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => TrainerSharingPage(
                          history: history.map((w) => w.toJson()).toList(),
                          onLinked: onTrainerLinked,
                        ),
                      ),
                    )
                  : () => showTrainerComingSoon(context),
            ),
          ),
          _sectionTitle('その他設定'),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                ListTile(
                  key: const Key('contactButton'),
                  leading: const Icon(Icons.support_agent_rounded),
                  title: const Text('お問い合わせ'),
                  subtitle: const Text('不具合報告・機能要望・その他'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const ContactPage()),
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                ListTile(
                  key: const Key('appAboutButton'),
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('アプリについて'),
                  subtitle: const Text('$appDisplayName ・ バージョン $appVersion'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const AppAboutPage()),
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle('バックアップ・データ管理'),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: ListTile(
              key: const Key('backupDataManagementButton'),
              leading: const Icon(Icons.backup_outlined),
              title: const Text('バックアップ・データ管理'),
              subtitle: const Text('書き出し・復元'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BackupDataManagementPage(
                    onExport: _shareBackup,
                    onImportFile: _restoreFromFile,
                    onCloudSync: onSyncRequested,
                    historyCount: history.length,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
    ),
  );

  Widget _trainingSettingsCard(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: Column(
      children: [
        ListTile(
          key: const Key('trainingSettingsButton'),
          leading: const Icon(Icons.fitness_center_rounded),
          title: const Text('トレーニング設定'),
          subtitle: const Text('セット完了チェック・休憩・トレーニング時間'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => TrainingSettingsPage(
                completionCheckEnabled: completionCheckEnabled,
                workoutTimerEnabled: workoutTimerEnabled,
                workoutDurationEnabled: workoutDurationEnabled,
                restTimerEnabled: restTimerEnabled,
                restTimerSeconds: restTimerSeconds,
                workoutTemplates: workoutTemplates,
                onCompletionCheckEnabledChanged:
                    onCompletionCheckEnabledChanged,
                onWorkoutTimerEnabledChanged: onWorkoutTimerEnabledChanged,
                onWorkoutDurationEnabledChanged:
                    onWorkoutDurationEnabledChanged,
                onRestTimerEnabledChanged: onRestTimerEnabledChanged,
                onRestTimerSecondsChanged: onRestTimerSecondsChanged,
                onWorkoutTemplatesChanged: onWorkoutTemplatesChanged,
                onCustomExercisesChanged: onCustomExercisesChanged,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  String _backupJson() => jsonEncode(
    SetkeepBackup(
      workouts: history,
      workoutTemplates: workoutTemplates,
      bodyWeights: bodyWeights,
      customExercises: CustomExercisePreference.exercises,
      customGyms: CustomGymPreference.gyms,
      selectedGym: selectedGym,
      restTimerEnabled: restTimerEnabled,
      restTimerSeconds: restTimerSeconds,
      completionCheckEnabled: completionCheckEnabled,
      workoutTimerEnabled: workoutTimerEnabled,
      workoutDurationEnabled: workoutDurationEnabled,
    ).toJson(),
  );

  Future<void> _shareBackup(BuildContext context) async {
    try {
      final now = DateTime.now();
      final date =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final fileName = 'setkeep_backup_$date.json';
      await SharePlus.instance.share(
        ShareParams(
          title: 'SETKEEP バックアップ',
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(_backupJson())),
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: [fileName],
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('バックアップを書き出せませんでした')));
    }
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    try {
      const jsonType = XTypeGroup(
        label: 'SETKEEP JSON',
        extensions: ['json'],
        uniformTypeIdentifiers: ['public.json'],
      );
      final file = await openFile(acceptedTypeGroups: [jsonType]);
      if (file == null) return;
      final source = await file.readAsString();
      if (!context.mounted) return;
      await _restoreText(context, source);
    } on FormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('このファイルはSETKEEPのバックアップとして読み込めません')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('バックアップファイルを開けませんでした')));
    }
  }

  Future<void> _restoreText(BuildContext context, String source) async {
    final decodedValue = jsonDecode(source);
    if (decodedValue is! Map<String, dynamic>) {
      throw const FormatException('Backup root must be an object');
    }
    final decoded = decodedValue;
    final backup = SetkeepBackup.fromJson(decoded);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('バックアップから復元しますか？'),
        content: const Text('現在のデータを残したまま、バックアップ内の記録と設定を追加・更新します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirmBackupRestoreButton'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('復元する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await onBackupImported(backup);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$count件の新しい記録と設定を読み込みました')));
  }
}

class _CustomRestDurationDialog extends StatefulWidget {
  const _CustomRestDurationDialog({required this.seconds});
  final int seconds;

  @override
  State<_CustomRestDurationDialog> createState() =>
      _CustomRestDurationDialogState();
}

class _CustomRestDurationDialogState extends State<_CustomRestDurationDialog> {
  final _form = GlobalKey<FormState>();
  late String _minutes = '${widget.seconds ~/ 60}';
  late String _seconds = '${widget.seconds % 60}';
  String? _error;

  String? _validate(String? value, String unit) {
    if (value == null || !RegExp(r'^\d+$').hasMatch(value)) {
      return '$unitは0〜59の整数で入力してください';
    }
    final number = int.tryParse(value);
    return number == null || number > 59 ? '$unitは0〜59で入力してください' : null;
  }

  void _save() {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final total = int.parse(_minutes) * 60 + int.parse(_seconds);
    if (total == 0) {
      setState(() => _error = '1秒以上の時間を設定してください');
      return;
    }
    Navigator.pop(context, total);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('休憩時間を設定'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('customRestMinutesField'),
              initialValue: _minutes,
              decoration: const InputDecoration(
                labelText: '分',
                errorMaxLines: 2,
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              validator: (value) => _validate(value, '分'),
              onChanged: (value) => _minutes = value,
            ),
            TextFormField(
              key: const Key('customRestSecondsField'),
              initialValue: _seconds,
              decoration: const InputDecoration(
                labelText: '秒',
                errorMaxLines: 2,
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              validator: (value) => _validate(value, '秒'),
              onChanged: (value) => _seconds = value,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      FilledButton(
        key: const Key('saveCustomRestDurationButton'),
        onPressed: _save,
        child: const Text('保存'),
      ),
    ],
  );
}

class TrainingSettingsPage extends StatefulWidget {
  const TrainingSettingsPage({
    super.key,
    required this.completionCheckEnabled,
    required this.workoutTimerEnabled,
    required this.workoutDurationEnabled,
    required this.restTimerEnabled,
    required this.restTimerSeconds,
    required this.workoutTemplates,
    required this.onCompletionCheckEnabledChanged,
    required this.onWorkoutTimerEnabledChanged,
    required this.onWorkoutDurationEnabledChanged,
    required this.onRestTimerEnabledChanged,
    required this.onRestTimerSecondsChanged,
    required this.onWorkoutTemplatesChanged,
    required this.onCustomExercisesChanged,
  });

  final bool completionCheckEnabled;
  final bool workoutTimerEnabled;
  final bool workoutDurationEnabled;
  final bool restTimerEnabled;
  final int restTimerSeconds;
  final List<SavedWorkoutTemplate> workoutTemplates;
  final ValueChanged<bool> onCompletionCheckEnabledChanged;
  final ValueChanged<bool> onWorkoutTimerEnabledChanged;
  final ValueChanged<bool> onWorkoutDurationEnabledChanged;
  final ValueChanged<bool> onRestTimerEnabledChanged;
  final ValueChanged<int> onRestTimerSecondsChanged;
  final Future<void> Function(List<SavedWorkoutTemplate>)
  onWorkoutTemplatesChanged;
  final VoidCallback onCustomExercisesChanged;

  @override
  State<TrainingSettingsPage> createState() => _TrainingSettingsPageState();
}

class _TrainingSettingsPageState extends State<TrainingSettingsPage> {
  late bool _completionCheckEnabled;
  late bool _workoutTimerEnabled;
  late bool _restTimerEnabled;
  late int _restTimerSeconds;
  late List<SavedWorkoutTemplate> _workoutTemplates;

  @override
  void initState() {
    super.initState();
    _completionCheckEnabled = widget.completionCheckEnabled;
    _workoutTimerEnabled =
        widget.workoutTimerEnabled || widget.workoutDurationEnabled;
    _restTimerEnabled = widget.restTimerEnabled && _completionCheckEnabled;
    _restTimerSeconds = widget.restTimerSeconds;
    _workoutTemplates = List<SavedWorkoutTemplate>.from(
      widget.workoutTemplates,
    );
  }

  Future<void> _updateWorkoutTemplates(
    List<SavedWorkoutTemplate> templates,
  ) async {
    setState(() {
      _workoutTemplates = List<SavedWorkoutTemplate>.from(templates);
    });
    await widget.onWorkoutTemplatesChanged(_workoutTemplates);
  }

  Future<void> _openCustomExercises() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CustomExerciseManagementPage()),
    );
    if (!mounted) return;
    setState(() {});
    widget.onCustomExercisesChanged();
  }

  String _durationLabel(int seconds) {
    if (seconds < 60) return '$seconds秒';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '$minutes分' : '$minutes分$remainder秒';
  }

  Future<void> _selectRestDuration() async {
    const durations = [30, 60, 90, 120, 180];
    var selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                '休憩時間',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ),
            ...durations.map(
              (seconds) => ListTile(
                key: Key('restDurationPreset$seconds'),
                title: Text(_durationLabel(seconds)),
                trailing: seconds == _restTimerSeconds
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primaryGreenStrong,
                      )
                    : null,
                onTap: () => Navigator.pop(context, seconds),
              ),
            ),
            ListTile(
              key: const Key('customRestDurationButton'),
              title: const Text('カスタム'),
              trailing: !durations.contains(_restTimerSeconds)
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primaryGreenStrong,
                    )
                  : null,
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == -1) {
      selected = await showDialog<int>(
        context: context,
        builder: (_) => _CustomRestDurationDialog(seconds: _restTimerSeconds),
      );
    }
    if (!mounted || selected == null) return;
    final seconds = selected;
    setState(() => _restTimerSeconds = seconds);
    widget.onRestTimerSecondsChanged(seconds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('トレーニング設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('completionCheckSwitch'),
                  secondary: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('セット完了チェック'),
                  subtitle: Text(
                    _completionCheckEnabled ? '丸チェックを表示' : '入力した全セットを記録',
                  ),
                  value: _completionCheckEnabled,
                  onChanged: (enabled) {
                    setState(() {
                      _completionCheckEnabled = enabled;
                      if (!enabled) _restTimerEnabled = false;
                    });
                    widget.onCompletionCheckEnabledChanged(enabled);
                  },
                ),
                if (_completionCheckEnabled) ...[
                  const Divider(height: 1, thickness: 0.5),
                  SwitchListTile(
                    key: const Key('restTimerSwitch'),
                    secondary: const Icon(Icons.timer_outlined),
                    title: const Text('休憩タイマー'),
                    subtitle: Text(_restTimerEnabled ? 'セット完了後に開始' : '使用しない'),
                    value: _restTimerEnabled,
                    onChanged: (enabled) {
                      setState(() => _restTimerEnabled = enabled);
                      widget.onRestTimerEnabledChanged(enabled);
                    },
                  ),
                  if (_restTimerEnabled) ...[
                    const Divider(height: 1, thickness: 0.5),
                    ListTile(
                      key: const Key('restTimerDurationButton'),
                      leading: const Icon(Icons.hourglass_bottom_rounded),
                      title: const Text('休憩時間'),
                      trailing: Text(
                        _durationLabel(_restTimerSeconds),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: _selectRestDuration,
                    ),
                  ],
                ],
                const Divider(height: 1, thickness: 0.5),
                SwitchListTile(
                  key: const Key('trainingDurationSwitch'),
                  secondary: const Icon(Icons.timer_outlined),
                  title: const Text('トレーニング時間'),
                  subtitle: Text(
                    _workoutTimerEnabled ? '記録中に計測し、完了後に履歴へ保存' : '計測・保存しない',
                  ),
                  value: _workoutTimerEnabled,
                  onChanged: (enabled) {
                    setState(() => _workoutTimerEnabled = enabled);
                    widget.onWorkoutTimerEnabledChanged(enabled);
                    widget.onWorkoutDurationEnabledChanged(enabled);
                  },
                ),
                const Divider(height: 1, thickness: 0.5),
                ListTile(
                  key: const Key('savedMenuManagementButton'),
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: const Text('マイメニュー管理'),
                  subtitle: Text(
                    _workoutTemplates.isEmpty
                        ? '保存なし'
                        : '${_workoutTemplates.length}件を保存中',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => SavedMenuManagementPage(
                        initialTemplates: _workoutTemplates,
                        onChanged: _updateWorkoutTemplates,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                ListTile(
                  key: const Key('customExerciseManagementButton'),
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('カスタム種目管理'),
                  subtitle: Text(
                    CustomExercisePreference.exercises.isEmpty
                        ? '登録なし'
                        : '${CustomExercisePreference.exercises.length}種目を登録中',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openCustomExercises,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              '休憩タイマーは、セット完了を付けたときに開始します。',
              style: TextStyle(fontSize: 12, color: Color(0xFF777F78)),
            ),
          ),
        ],
      ),
    );
  }
}

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({
    super.key,
    required this.historyCount,
    required this.onSyncRequested,
    this.auth,
    this.showBackupSection = true,
  });

  final int historyCount;
  final Future<int> Function() onSyncRequested;
  final AccountAuthService? auth;
  final bool showBackupSection;

  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  static const _authStateErrorMessage = 'ログイン状態を確認できませんでした。もう一度お試しください。';
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  bool _isSignUp = false;
  late final AccountAuthService? _auth;
  StreamSubscription<void>? _authSubscription;
  bool _busy = false;
  bool _confirmingDeletion = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? SupabaseAccountAuthService.configured();
    _authSubscription = _auth?.changes.listen(
      (_) {
        if (!mounted) return;
        _passwordController.clear();
        _passwordConfirmationController.clear();
        setState(() {
          if (_auth?.isSignedIn == true) _isSignUp = false;
          if (_message == _authStateErrorMessage) _message = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        // Callback errors arrive after the browser launch Future completes.
        // Do not expose raw SDK errors, which may include connection values.
        setState(() {
          _busy = false;
          _message = _authStateErrorMessage;
        });
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      _message = error.message;
    } catch (_) {
      _message = '通信に失敗しました。接続を確認してください。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleAuthMode() {
    if (_busy) return;
    final email = _emailController.text;
    _formKey.currentState?.reset();
    _emailController.text = email;
    _passwordController.clear();
    _passwordConfirmationController.clear();
    setState(() {
      _isSignUp = !_isSignUp;
      _message = null;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _auth!.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        _passwordController.clear();
        _passwordConfirmationController.clear();
      }
      _message = 'ログインしました';
    });
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      final hasSession = await _auth!.signUp(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        _passwordController.clear();
        _passwordConfirmationController.clear();
      }
      _message = hasSession
          ? 'アカウントを作成しました'
          : '確認メールを送りました。メールを開いて登録を完了してください。';
    });
  }

  Future<void> _signInWithGoogle() => _run(() => _auth!.signInWithGoogle());

  Future<void> _signOut() => _run(() async {
    await _auth!.signOut();
    _message = 'ログアウトしました';
  });

  Future<void> _deleteAccount() => _run(() async {
    final email = _auth!.email;
    _confirmingDeletion = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: Text(
          '${email ?? ''}\n\n'
          'アカウントと本人のクラウド上のトレーニング記録、フレンド共有を削除します。'
          'TRAINER連携は解除します。他の利用者や組織の記録は残ります。'
          'この操作は取り消せません。\n\n'
          'この端末のトレーニング記録は残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const Key('accountDeleteConfirmButton'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    _confirmingDeletion = false;
    if (confirmed != true || !mounted) return;
    setState(() {});
    if (_auth?.isSignedIn != true || _auth?.email != email) {
      _message = 'ログイン状態が変わりました。もう一度お試しください。';
      return;
    }
    await _auth!.deleteAccount();
    _message = 'アカウントを削除しました。この端末のトレーニング記録は残っています。';
  });

  Future<void> _sync() => _run(() async {
    // Entitlement is checked only for cloud operations, never authentication.
    SupabaseSyncService.requirePremium();
    if (!_auth!.isSignedIn) return;
    final count = await widget.onSyncRequested();
    _message = '$count件の記録を同期しました';
  });

  Widget _emailForm() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('accountEmailField'),
          controller: _emailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'メールアドレス',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'メールアドレスを入力してください';
            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
              return 'メールアドレスの形式を確認してください';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('accountPasswordField'),
          controller: _passwordController,
          enabled: !_busy,
          textInputAction: _isSignUp
              ? TextInputAction.next
              : TextInputAction.done,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'パスワード（6文字以上）',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              (value?.length ?? 0) < 6 ? 'パスワードは6文字以上で入力してください' : null,
        ),
        if (_isSignUp) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('accountPasswordConfirmationField'),
            controller: _passwordConfirmationController,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'パスワード確認',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '確認用のパスワードを入力してください';
              }
              if (value != _passwordController.text) {
                return 'パスワードが一致しません';
              }
              return null;
            },
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: Key(_isSignUp ? 'accountSignUpButton' : 'accountSignInButton'),
          onPressed: _busy ? null : (_isSignUp ? _signUp : _signIn),
          child: Text(_isSignUp ? 'アカウントを作成' : 'ログイン'),
        ),
        TextButton(
          key: const Key('accountAuthModeButton'),
          onPressed: _busy ? null : _toggleAuthMode,
          child: Text(
            _isSignUp ? 'すでにアカウントをお持ちの方 → ログイン' : 'アカウントをお持ちでない方 → 新規アカウント作成',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final signedIn = _auth?.isSignedIn ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(!signedIn && _isSignUp ? 'アカウントを作成' : 'アカウント'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_auth == null)
            const Text('現在アカウント機能を利用できません')
          else if (!signedIn) ...[
            OutlinedButton(
              key: const Key('accountGoogleSignInButton'),
              onPressed: _busy ? null : _signInWithGoogle,
              child: const Text('Googleで続ける'),
            ),
            const SizedBox(height: 20),
            _emailForm(),
          ] else ...[
            const Text(
              'ログイン中',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(_auth?.email ?? '', key: const Key('accountSignedInEmail')),
            TextButton(
              key: const Key('accountSignOutButton'),
              onPressed: _busy ? null : _signOut,
              child: const Text('ログアウト'),
            ),
            TextButton(
              key: const Key('accountDeleteButton'),
              onPressed: _busy ? null : _deleteAccount,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('アカウントを削除'),
            ),
          ],
          if (_busy && !_confirmingDeletion) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, textAlign: TextAlign.center),
          ],
          if (widget.showBackupSection) ...[
            const SizedBox(height: 24),
            CloudBackupSection(
              premium: SupabaseSyncService.canUseCloud,
              onOpen: signedIn && !_busy ? _sync : null,
            ),
          ],
        ],
      ),
    );
  }
}

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _category = '不具合報告';
  image_picker.XFile? _attachment;
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await image_picker.ImagePicker().pickImage(
      source: image_picker.ImageSource.gallery,
      maxWidth: 2160,
      imageQuality: 90,
    );
    if (image != null && mounted) setState(() => _attachment = image);
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate() || _sending) return;
    setState(() => _sending = true);
    try {
      final device = await DeviceInfoService.summary();
      final text =
          '''お問い合わせ種別：$_category

${_messageController.text.trim()}

---
アプリ：$appDisplayName $appVersion
端末：$device''';
      await SharePlus.instance.share(
        ShareParams(
          subject: '[$_category] ${_subjectController.text.trim()}',
          title: '$appDisplayNameへのお問い合わせ',
          text: text,
          files: _attachment == null ? const [] : [XFile(_attachment!.path)],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('送信画面を開けませんでした')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お問い合わせ')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            DropdownButtonFormField<String>(
              key: const Key('contactCategoryField'),
              initialValue: _category,
              decoration: const InputDecoration(labelText: '問い合わせ種別'),
              items: const [
                DropdownMenuItem(value: '不具合報告', child: Text('不具合報告')),
                DropdownMenuItem(value: '機能要望', child: Text('機能要望')),
                DropdownMenuItem(value: 'その他問い合わせ', child: Text('その他問い合わせ')),
              ],
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('contactSubjectField'),
              controller: _subjectController,
              maxLength: 80,
              decoration: const InputDecoration(labelText: '件名'),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '件名を入力してください' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('contactMessageField'),
              controller: _messageController,
              minLines: 6,
              maxLines: 12,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '問い合わせ内容',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '問い合わせ内容を入力してください' : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('contactImageButton'),
              onPressed: _pickImage,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(_attachment == null ? '画像を添付（任意）' : '添付画像を変更'),
            ),
            if (_attachment != null)
              TextButton.icon(
                onPressed: () => setState(() => _attachment = null),
                icon: const Icon(Icons.close_rounded),
                label: const Text('添付を外す'),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('sendContactButton'),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded),
              label: Text(_sending ? '準備中…' : '送信方法を選ぶ'),
            ),
            const SizedBox(height: 10),
            const Text(
              '送信先の受付窓口は未設定です。端末の共有画面からメールなどを選んで送信できます。',
              style: TextStyle(fontSize: 12, color: Color(0xFF6C746D)),
            ),
          ],
        ),
      ),
    );
  }
}

class AppAboutPage extends StatelessWidget {
  const AppAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アプリについて')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.primaryGreen,
                    child: Icon(Icons.fitness_center_rounded, size: 34),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    appDisplayName,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'バージョン $appVersion',
                    style: TextStyle(color: Color(0xFF6C746D)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '今日の1セットを、次の成長につなげるトレーニング記録アプリです。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.phone_iphone_rounded),
                  title: Text('端末内への保存'),
                  subtitle: Text('記録と設定は、この端末内に保存されます'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('クラウド同期'),
                  subtitle: Text('Supabaseを設定した場合だけ利用できます'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('バックアップ'),
                  subtitle: Text('マイページからJSON形式で書き出し・復元できます'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
