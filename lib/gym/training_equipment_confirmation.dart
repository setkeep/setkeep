import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../exercise_list_thumbnail.dart';

/// Created only from saved history, never a draft or a planned trainer menu.
class EquipmentWorkout {
  const EquipmentWorkout({
    required this.key,
    required this.storeId,
    required this.exercises,
    required this.completed,
  });
  final String key;
  final String? storeId;
  final Map<String, String>
  exercises; // Completed, valid set exercise ID -> name.
  final bool completed;
  bool get eligible => completed && storeId != null && exercises.isNotEmpty;
}

abstract class TrainingEquipmentRepository {
  String? get userId;
  Future<List<Map<String, dynamic>>> options(String storeId, List<String> ids);
  Future<void> confirm(Map<String, dynamic> receipt, bool performed);
}

class SupabaseTrainingEquipmentRepository
    implements TrainingEquipmentRepository {
  @override
  String? get userId => SupabaseConfig.initialized
      ? Supabase.instance.client.auth.currentUser?.id
      : null;
  @override
  Future<List<Map<String, dynamic>>> options(
    String storeId,
    List<String> ids,
  ) async => List<Map<String, dynamic>>.from(
    await Supabase.instance.client.rpc(
      'training_equipment_options',
      params: {'target_store': storeId, 'exercise_ids': ids},
    ),
  );
  @override
  Future<void> confirm(Map<String, dynamic> receipt, bool performed) async {
    if (userId != receipt['user_id']) return;
    await Supabase.instance.client.rpc(
      'confirm_training_equipment',
      params: {
        'target_store': receipt['store_id'],
        'target_equipment': receipt['equipment_id'],
        'target_exercise': receipt['exercise_id'],
        'record_key': receipt['workout_key'],
        'performed': performed,
        'expected_user': receipt['user_id'],
      },
    );
  }
}

class TrainingEquipmentServices {
  static TrainingEquipmentRepository repository =
      SupabaseTrainingEquipmentRepository();
  static TrainingEquipmentJournal journal = TrainingEquipmentJournal(
    () => repository,
  );
}

/// At most one latest consent per local account/store/equipment. History stays
/// in its existing store. Persisted intent survives offline edits, deletion,
/// Undo and restart; withdrawal only targets the same server workout key.
class TrainingEquipmentJournal {
  TrainingEquipmentJournal(this.repository);
  final TrainingEquipmentRepository Function() repository;
  static const storageKey = 'training_equipment_consents_v1';
  Future<void>? _tail;
  Future<void> _serial(Future<void> Function() action) {
    final next = _tail?.then((_) => action()) ?? action();
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<List<Map<String, dynamic>>> _read(SharedPreferences prefs) async {
    return List<Map<String, dynamic>>.from(
      jsonDecode(prefs.getString(storageKey) ?? '[]') as List,
    );
  }

  Future<void> _write(
    SharedPreferences prefs,
    List<Map<String, dynamic>> rows,
  ) async {
    if (!await prefs.setString(storageKey, jsonEncode(rows))) {
      throw StateError('Equipment confirmation could not be saved');
    }
  }

  Future<void> remember(
    EquipmentWorkout workout,
    List<Map<String, dynamic>> choices,
  ) {
    final user = repository().userId;
    return _serial(() async {
      if (!workout.eligible || user == null || repository().userId != user) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final rows = await _read(prefs);
      for (final choice in choices) {
        if (!workout.exercises.containsKey(choice['exercise_id'])) continue;
        rows.removeWhere(
          (r) =>
              r['user_id'] == user &&
              r['store_id'] == workout.storeId &&
              r['equipment_id'] == choice['equipment_id'],
        );
        rows.add({
          'user_id': user,
          'store_id': workout.storeId,
          'equipment_id': choice['equipment_id'],
          'exercise_id': choice['exercise_id'],
          'workout_key': workout.key,
          'sent': null,
        });
      }
      await _write(prefs, rows);
    });
  }

  Future<void> reconcile(List<EquipmentWorkout> history) {
    final repo = repository(), user = repository().userId;
    return _serial(() async {
      if (user == null || repo.userId != user) return;
      final prefs = await SharedPreferences.getInstance();
      final rows = await _read(prefs);
      for (final r in rows.where((r) => r['user_id'] == user)) {
        if (repo.userId != user) return;
        final valid = history.any(
          (w) =>
              w.eligible &&
              w.key == r['workout_key'] &&
              w.storeId == r['store_id'] &&
              w.exercises.containsKey(r['exercise_id']),
        );
        if (r['sent'] == valid) continue;
        try {
          await repo.confirm(r, valid).timeout(const Duration(seconds: 8));
          if (repo.userId != user) return;
          r['sent'] = valid;
          await _write(prefs, rows);
        } catch (_) {
          // Consent remains durable. Retry on foreground/auth/history change.
          return;
        }
      }
    });
  }
}

final _equipmentPromptsInFlight = <String>{};

Future<void> confirmWorkoutEquipment(
  BuildContext context,
  EquipmentWorkout workout,
) async {
  final user = TrainingEquipmentServices.repository.userId;
  if (!workout.eligible || user == null) return;
  final key = '$user|${workout.storeId}|${workout.key}';
  if (!_equipmentPromptsInFlight.add(key)) return;
  try {
    await _confirmWorkoutEquipment(context, workout);
  } finally {
    _equipmentPromptsInFlight.remove(key);
  }
}

Future<void> _confirmWorkoutEquipment(
  BuildContext context,
  EquipmentWorkout workout,
) async {
  final repo = TrainingEquipmentServices.repository;
  final user = repo.userId;
  if (!workout.eligible || user == null) return;
  List<Map<String, dynamic>> rows;
  try {
    rows = await repo
        .options(workout.storeId!, workout.exercises.keys.toList())
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    // Recording/completion must never depend on this optional network feature.
    return;
  }
  if (!context.mounted || repo.userId != user) return;
  final seen = <String>{};
  final prompts = rows
      .where(
        (r) =>
            workout.exercises.containsKey(r['exercise_id']) &&
            (r['options'] as List).any((o) => o['known'] != true),
      )
      .toList();
  prompts.removeWhere((r) {
    final ids =
        (r['options'] as List).map((o) => o['equipment_id'] as String).toList()
          ..sort();
    return !seen.add(ids.join('|'));
  });
  if (prompts.isEmpty) return;
  final choices = await showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TrainingEquipmentSheet(workout: workout, prompts: prompts),
  );
  if (choices == null || choices.isEmpty || repo.userId != user) return;
  try {
    await TrainingEquipmentServices.journal.remember(workout, choices);
  } catch (_) {
    // Workout was already saved; never roll it back for equipment feedback.
  }
}

class TrainingEquipmentSheet extends StatefulWidget {
  const TrainingEquipmentSheet({
    super.key,
    required this.workout,
    required this.prompts,
  });
  final EquipmentWorkout workout;
  final List<Map<String, dynamic>> prompts;
  @override
  State<TrainingEquipmentSheet> createState() => _TrainingEquipmentSheetState();
}

class _TrainingEquipmentSheetState extends State<TrainingEquipmentSheet> {
  final selected = <String, Map<String, dynamic>>{};
  String choiceKey(String exercise, Map<String, dynamic> option) =>
      '$exercise|${option['equipment_id']}';
  @override
  void initState() {
    super.initState();
    for (final prompt in widget.prompts) {
      final options = List<Map<String, dynamic>>.from(
        prompt['options'] as List,
      );
      if (options.length != 1 || options.single['known'] == true) continue;
      final option = options.single;
      final label = option['label'] as String;
      // Reviewed workout options only. Free weights/bodyweight never imply a machine.
      if (!RegExp(r'マシン|ケーブル|スミス|レッグプレス|ラットプル|ペック|バタフライ|トレッドミル|エルゴ')
          .hasMatch(label)) {
        continue;
      }
      final exercise = prompt['exercise_id'] as String;
      selected[choiceKey(exercise, option)] = {
        ...option,
        'exercise_id': exercise,
      };
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .7,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                '今回使用した設備を確認',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text('この店舗のマシン情報を集めています。今回使った候補に間違いがあれば解除してください。スキップできます。'),
              Text('画像は共通の種目イメージです。店舗の設備写真ではありません。'),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final prompt in widget.prompts)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ExerciseListThumbnail(
                            exerciseId: prompt['exercise_id'] as String,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.workout.exercises[prompt['exercise_id']]!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final raw in prompt['options'] as List)
                            ChoiceChip(
                              label: Text(
                                '${raw['label']}${raw['known'] == true ? '（確認済み）' : ''}',
                              ),
                              selected: selected.containsKey(
                                choiceKey(
                                  prompt['exercise_id'] as String,
                                  Map<String, dynamic>.from(raw),
                                ),
                              ),
                              onSelected: (value) => setState(() {
                                if (value) {
                                  selected[choiceKey(
                                    prompt['exercise_id'] as String,
                                    Map<String, dynamic>.from(raw),
                                  )] = {
                                    ...Map<String, dynamic>.from(raw),
                                    'exercise_id': prompt['exercise_id'],
                                  };
                                } else {
                                  selected.remove(
                                    choiceKey(
                                      prompt['exercise_id'] as String,
                                      Map<String, dynamic>.from(raw),
                                    ),
                                  );
                                }
                              }),
                            ),
                          ActionChip(
                            label: const Text('その他 / 判定しない'),
                            onPressed: () => setState(
                              () => selected.removeWhere(
                                (key, value) =>
                                    value['exercise_id'] ==
                                    prompt['exercise_id'],
                              ),
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('スキップ'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, [
                      for (final entry in selected.entries)
                        if (entry.value['known'] != true)
                          {
                            'exercise_id': entry.value['exercise_id'],
                            'equipment_id': entry.value['equipment_id'],
                          },
                    ]),
                    child: const Text('この内容で送信'),
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
