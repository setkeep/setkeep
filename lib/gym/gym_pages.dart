import 'dart:async';

import 'gym_equipment_cache.dart';

import 'package:flutter/material.dart';

import '../design/app_colors.dart';

import '../exercise_form_catalog.dart';
import '../config/supabase_config.dart';
import 'gym_repository.dart';
import 'store_report_sheet.dart';
import 'training_place_preference.dart';
import 'custom_gym_preference.dart';
import 'place_equipment_pages.dart';

Widget gymError(VoidCallback retry) => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    children: [
      Text(
        GymServices.override == null && !SupabaseConfig.initialized
            ? '店舗情報への接続設定が読み込まれていません。アカウント画面の状態も確認してください。アプリの再起動で改善しない場合は、接続設定を含むアプリへの更新が必要です。'
            : '店舗情報を取得できませんでした。通信状態を確認してください。',
      ),
      TextButton(onPressed: retry, child: const Text('再読み込み')),
    ],
  ),
);

List<MapEntry<String, String>> sortedGymChainOptions(
  Map<String, String> chains,
) {
  String sortKey(String name) {
    final kanaAndAscii = String.fromCharCodes(
      name.runes.map((code) {
        if (code >= 0x30a1 && code <= 0x30f6) return code - 0x60;
        if (code >= 0xff21 && code <= 0xff3a) return code - 0xff21 + 0x61;
        if (code >= 0xff41 && code <= 0xff5a) return code - 0xff41 + 0x61;
        return code;
      }),
    );
    final normalized = kanaAndAscii.toLowerCase().replaceAll(
      RegExp(r"[\s'’+＋・･‐‑–—−－-]"),
      '',
    );
    return '${RegExp(r'^[a-z]').hasMatch(normalized) ? '0' : '1'}$normalized';
  }

  final options = chains.entries
      .where((entry) => entry.key != 'kanekin-fitness-gym')
      .toList();
  options.sort((a, b) {
    final byName = sortKey(a.value).compareTo(sortKey(b.value));
    return byName != 0 ? byName : a.key.compareTo(b.key);
  });
  return options;
}

class GymStoreSearchPage extends StatefulWidget {
  const GymStoreSearchPage({super.key});
  @override
  State<GymStoreSearchPage> createState() => _GymStoreSearchPageState();
}

class _GymStoreSearchPageState extends State<GymStoreSearchPage> {
  final _repo = GymServices.repository;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GymStore> _stores = [], _registered = [];
  bool _busy = true, _failed = false, _more = false;
  int _request = 0;
  bool _registeredFailed = false;
  Map<String, String> _chains = {};
  String? _chain;
  @override
  void initState() {
    super.initState();
    _load();
    _loadChains();
  }

  Future<void> _loadChains() async {
    try {
      final chains = await _repo.chains();
      if (mounted) setState(() => _chains = chains);
    } catch (_) {
      /* Search remains usable without optional chain choices. */
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      var registered = _registered;
      var registeredFailed = _registeredFailed;
      if (!more) {
        try {
          registered = await _repo.registered();
          registeredFailed = false;
        } catch (_) {
          registered = [];
          registeredFailed = true;
        }
      }
      final rows = await _repo.searchStores(
        _controller.text,
        offset: more ? _stores.length : 0,
        chainId: _chain,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _registered = registered
            .where((s) => _chain == null || s.chainId == _chain)
            .toList();
        _registeredFailed = registeredFailed;
        _stores = more ? [..._stores, ...rows] : rows;
        _more = rows.length == 30;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Widget _tile(GymStore s) => ListTile(
    key: ValueKey('selectGymStore${s.id}'),
    leading: const Icon(Icons.location_on_outlined),
    title: Text(s.displayName),
    subtitle: Text(
      [
        s.city,
        if (!s.isSelectable) s.statusLabel,
      ].whereType<String>().where((v) => v.isNotEmpty).join(' ・ '),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      final chosen = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GymStoreEquipmentPage(
            store: s,
            onSelect: () => Navigator.pop(context, true),
          ),
        ),
      );
      if (chosen == true && mounted) Navigator.pop(context, s);
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('店舗を探す')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('gymStoreSearchField'),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '店舗名・地域・チェーン名で検索',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                ++_request;
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _load(),
                );
              },
              onSubmitted: (_) {
                _debounce?.cancel();
                _load();
              },
            ),
          ),
          if (_chains.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                key: const Key('gymChainFilter'),
                initialValue: _chain ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'チェーンで絞り込む（任意）'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('すべてのチェーン')),
                  for (final e in sortedGymChainOptions(_chains))
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  setState(() => _chain = v == '' ? null : v);
                  _load();
                },
              ),
            ),
          ListTile(
            key: const Key('registerManualPlace'),
            title: const Text('探しているジムがありませんか？'),
            subtitle: const Text('自分で利用場所を登録'),
            trailing: const Icon(Icons.add),
            onTap: () async {
              await CustomGymPreference.load();
              if (!context.mounted) return;
              final name = await addCustomGym(context);
              if (name != null && context.mounted) {
                Navigator.pop(context, TrainingPlace.manual(name));
              }
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                TextButton.icon(
                  key: const Key('reportMissingStore'),
                  onPressed: () => showGymStoreReport(context),
                  icon: const Icon(Icons.outlined_flag),
                  label: const Text('掲載されていない店舗を報告'),
                ),
                if (_controller.text.trim().isEmpty &&
                    _registered.isNotEmpty) ...[
                  const ListTile(title: Text('登録済み店舗')),
                  ..._registered.map(_tile),
                  const Divider(),
                ],
                if (_registeredFailed && !_failed)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('登録済み店舗を読み込めませんでした。店舗検索は利用できます。'),
                  ),
                if (_failed) gymError(() => _load()),
                if (!_busy && !_failed && _stores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('検索結果がありません。別の店舗名・チェーン名でお試しください。'),
                  ),
                ..._stores
                    .where(
                      (s) =>
                          _controller.text.trim().isNotEmpty ||
                          !_registered.any((r) => r.id == s.id),
                    )
                    .map(_tile),
                if (_more && !_failed)
                  TextButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('さらに表示'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class RegisteredGymsPage extends StatefulWidget {
  const RegisteredGymsPage({super.key});
  @override
  State<RegisteredGymsPage> createState() => _RegisteredGymsPageState();
}

class _RegisteredGymsPageState extends State<RegisteredGymsPage> {
  final _repo = GymServices.repository;
  List<GymStore> _stores = [];
  TrainingPlace _defaultPlace = const TrainingPlace.home();
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await TrainingPlacePreference.migrateKanekinPlace(_repo);
      await CustomGymPreference.load();
      final savedPlace = await TrainingPlacePreference.load();
      if (mounted) setState(() => _defaultPlace = savedPlace);
      final stores = await _repo.registered();
      final place = await TrainingPlacePreference.reconcile(stores);
      if (mounted) {
        setState(() {
          _stores = stores;
          _defaultPlace = place;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final store = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const GymStoreSearchPage()),
    );
    if (store == null || !mounted) return;
    if (store is TrainingPlace) {
      await _load();
    } else if (store is GymStore) {
      await _change(() => _repo.register(store));
    }
  }

  Future<void> _change(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('利用場所を保存できませんでした。再度お試しください。')),
        );
      }
    }
  }

  bool _samePlace(TrainingPlace a, TrainingPlace b) =>
      a.isHome && b.isHome ||
      a.storeId != null && a.storeId == b.storeId ||
      a.manualName != null && a.manualName == b.manualName;

  Future<void> _manualAction(String name, String action) async {
    if (action == 'rename') {
      final updated = await showCustomGymDialog(context, initialName: name);
      if (updated == null || !mounted) return;
      await _change(() async {
        if (await CustomGymPreference.update(name, updated) &&
            _defaultPlace.manualName == name) {
          await TrainingPlacePreference.save(TrainingPlace.manual(updated));
        }
      });
    } else {
      await _change(() async {
        await CustomGymPreference.remove(name);
        if (_defaultPlace.manualName == name) {
          await TrainingPlacePreference.save(const TrainingPlace.home());
        }
      });
    }
  }

  Future<void> _removeStore(GymStore store) => _change(() async {
    await _repo.unregister(store.id);
    if (_defaultPlace.storeId == store.id) {
      await TrainingPlacePreference.save(const TrainingPlace.home());
    }
  });

  Widget _placeTile(TrainingPlace place, {required bool featured}) {
    final store = place.store;
    final name = place.manualName;
    final canChoose = store?.isSelectable != false;
    final open = place.isHome
        ? null
        : () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => store != null
                  ? GymStoreEquipmentPage(store: store)
                  : PrivatePlaceEquipmentPage(
                      placeId: place.customPlaceId!,
                      name: place.name,
                    ),
            ),
          );
    return Padding(
      key: place.isHome
          ? const Key('trainingPlaceHome')
          : name != null
          ? ValueKey('manualPlace$name')
          : ValueKey('registeredPlace${store!.id}'),
      padding: EdgeInsets.fromLTRB(
        16,
        featured ? 18 : 12,
        8,
        featured ? 16 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (place.isHome) ...[
                const Icon(Icons.home_outlined, size: 28),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: featured && store != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.chainName,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            store.name,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      )
                    : Text(
                        place.name,
                        style: TextStyle(
                          fontSize: featured ? 21 : 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              if (store != null)
                PopupMenuButton<String>(
                  key: ValueKey('removeRegisteredGym${store.id}'),
                  tooltip: '${place.name}を管理',
                  enabled: !_busy,
                  onSelected: (_) => _removeStore(store),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'remove', child: Text('利用場所から削除')),
                  ],
                )
              else if (name != null)
                PopupMenuButton<String>(
                  key: ValueKey('manualPlaceActions$name'),
                  tooltip: '$nameを管理',
                  enabled: !_busy,
                  onSelected: (action) => _manualAction(name, action),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('名前を変更')),
                    PopupMenuItem(value: 'delete', child: Text('削除')),
                  ],
                ),
            ],
          ),
          if (!canChoose)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${store!.statusLabel} ・ 過去情報を参照できます'),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (open != null)
                TextButton.icon(
                  onPressed: open,
                  icon: const Icon(Icons.fitness_center, size: 20),
                  label: const Text('設備を見る  ›'),
                ),
              if (featured)
                Container(
                  key: const Key('preferredTrainingPlaceBadge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0FFA1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 20,
                        color: Color(0xFF234000),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'いつもの場所',
                        style: TextStyle(
                          color: Color(0xFF234000),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              else
                TextButton.icon(
                  key: store != null
                      ? ValueKey('defaultTrainingPlace${store.id}')
                      : name != null
                      ? ValueKey('defaultManualPlace$name')
                      : const Key('defaultTrainingPlaceHome'),
                  onPressed: _busy || !canChoose
                      ? null
                      : () =>
                            _change(() => TrainingPlacePreference.save(place)),
                  icon: const Icon(Icons.push_pin_outlined, size: 19),
                  label: const Text('いつもの場所に設定'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = <TrainingPlace>[
      const TrainingPlace.home(),
      ..._stores.map(TrainingPlace.store),
      ...CustomGymPreference.gyms.map(TrainingPlace.manual),
    ];
    final preferred =
        places.where((p) => _samePlace(p, _defaultPlace)).firstOrNull ??
        _defaultPlace;
    final others = places.where((p) => !_samePlace(p, preferred)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('利用場所')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Text('登録した場所は自分だけに表示されます。\n未ログイン時はこの端末に保存します。'),
            if (_busy) const LinearProgressIndicator(),
            if (_failed) gymError(_load),
            const SizedBox(height: 24),
            const Text(
              'いつもの場所',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Card(
              key: const Key('preferredTrainingPlaceCard'),
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: _placeTile(preferred, featured: true),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'その他の場所',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Card(
                key: const Key('otherTrainingPlaces'),
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < others.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1),
                        ),
                      _placeTile(others[i], featured: false),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('registerGymButton'),
              onPressed: _busy ? null : _add,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              icon: const Icon(Icons.add),
              label: const Text('ジムを追加'),
            ),
          ],
        ),
      ),
    );
  }
}

class GymStoreEquipmentPage extends StatefulWidget {
  const GymStoreEquipmentPage({
    super.key,
    required this.store,
    this.onAdd,
    this.existingIds = const {},
    this.onSelect,
  });
  final GymStore store;
  final Future<void> Function(Set<String>)? onAdd;
  final Set<String> existingIds;
  final VoidCallback? onSelect;
  @override
  State<GymStoreEquipmentPage> createState() => _GymStoreEquipmentPageState();
}

Set<ExerciseFormDefinition> availableForms(Iterable<String> ids) => ids
    .map(ExerciseFormCatalog.canonicalDefinition)
    .whereType<ExerciseFormDefinition>()
    .where((f) => f.selectable)
    .toSet();

class _GymStoreEquipmentPageState extends State<GymStoreEquipmentPage>
    with WidgetsBindingObserver {
  final _repo = GymServices.repository;
  GymStoreDetail? _detail;
  Set<String> _pending = {};
  late final Set<String> _added = {...widget.existingIds};
  bool _busy = true, _failed = false;
  String _query = '';
  int _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Approvals and connectivity may change while this page stays open.
      // Keep existing rows until the refreshed response succeeds.
      unawaited(_load(force: true));
    }
  }

  Future<void> _load({bool force = false}) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final cached = force ? null : await GymEquipmentCache.read(widget.store.id);
    if (!mounted || request != _request) return;
    if (cached != null) setState(() => _detail = cached.detail);
    try {
      final detail = await _repo.detail(widget.store);
      if (!mounted || request != _request) return;
      setState(() => _detail = detail);
      await GymEquipmentCache.write(detail);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
    await _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final pending = await _repo.pendingEquipment(widget.store.id);
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      /* Private report lookup never blocks public equipment. */
    }
  }

  Future<void> _report(GymEquipment? equipment) async {
    final sent = await showGymEquipmentReport(context, widget.store, equipment);
    if (!mounted) return;
    if (sent && equipment != null) setState(() => _pending.add(equipment.id));
    await _loadReports();
    if (sent) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = _detail?.store ?? widget.store;
    final equipment = _detail?.equipment ?? [];
    final visible = equipment.where((e) => e.matches(_query)).toList()
      ..sort((a, b) {
        final c = a.displayCategory.compareTo(b.displayCategory);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    final categories = visible.map((e) => e.displayCategory).toSet();
    final forms = availableForms(_detail?.exerciseIds ?? {});
    final parts = <String, int>{};
    for (final f in forms) {
      parts.update(f.category, (v) => v + 1, ifAbsent: () => 1);
    }
    final counts = <String, int>{};
    for (final e in equipment) {
      counts.update(e.displayCategory, (v) => v + 1, ifAbsent: () => 1);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(store.displayName, maxLines: 2),
        actions: [
          IconButton(
            key: const Key('reportNewGymEquipment'),
            tooltip: '設備情報を報告',
            icon: const Icon(Icons.outlined_flag),
            onPressed: () => _report(null),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (store.city != null) Text(store.city!),
              if (!store.isSelectable && !store.isPreopening)
                Text('${store.statusLabel}。現在の利用場所には選択できません。過去の記録は保持されます。'),
              TextButton.icon(
                key: const Key('reportGymStore'),
                onPressed: () => showGymStoreReport(context, store: store),
                icon: const Icon(Icons.outlined_flag),
                label: const Text('店舗情報を報告'),
              ),
              if (store.isPreopening)
                const Text('この店舗はオープン準備中です。現在の利用場所には登録できません。'),
              if (widget.onSelect != null)
                FilledButton(
                  key: const Key('confirmGymStoreSelection'),
                  onPressed: store.isSelectable ? widget.onSelect : null,
                  child: const Text('この店舗を登録'),
                ),
              const SizedBox(height: 12),
              Text(
                '対応 ${forms.length}種目',
                key: const Key('gymTotalExerciseCount'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 12,
                children: [
                  for (final p in parts.entries) Text('${p.key} ${p.value}種目'),
                ],
              ),
              Wrap(
                spacing: 12,
                children: [
                  for (final c in counts.entries) Text('${c.key} ${c.value}設備'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('gymEquipmentSearch'),
                decoration: const InputDecoration(
                  labelText: '設備名で検索',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_failed && _detail != null)
                const Text('更新できませんでした。前回取得した設備情報を表示しています。'),
              if (_failed && _detail == null)
                gymError(() => _load(force: true)),
              if (!_busy && !_failed && equipment.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    store.communityEquipmentOnly
                        ? '設備募集中です。この店舗を選んでトレーニングを記録すると、使用設備を確認できます。利用者の確認が集まると設備一覧に反映します。「設備情報を報告」からの登録もできます。'
                        : 'この店舗の設備情報は未取得、または一部しか取得できていない可能性があります。通常の種目追加をご利用ください。',
                  ),
                ),
              if (equipment.isNotEmpty && visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('該当する設備がありません'),
                ),
              for (final category in categories) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    category,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final e in visible.where(
                  (e) => e.displayCategory == category,
                ))
                  Card(
                    child: ListTile(
                      key: ValueKey('gymEquipment${e.id}'),
                      title: Text(e.name),
                      subtitle: Text(
                        [
                          if (!e.usable) '一時利用不可',
                          if (e.usable &&
                              e.quantity != null &&
                              (e.unavailableQuantity ?? 0) > 0)
                            '${e.quantity}台中${e.quantity! - e.unavailableQuantity!}台利用可能'
                          else if (e.quantity != null)
                            '${e.quantity}台',
                          '対応${availableForms(_detail!.forEquipment(e.id).map((r) => r.exerciseId)).length}種目',
                          if (_detail!.forEquipment(e.id).isEmpty)
                            '対応種目は現在準備中です',
                          if (_pending.contains(e.id)) '確認中',
                        ].join(' ・ '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GymEquipmentExercisesPage(
                              store: store,
                              equipment: e,
                              evidence: _detail!.forEquipment(e.id),
                              existingIds: _added,
                              pending: _pending.contains(e.id),
                              onAdd: widget.onAdd == null
                                  ? null
                                  : (ids) async {
                                      await widget.onAdd!(ids);
                                      _added.addAll(ids);
                                    },
                            ),
                          ),
                        );
                        await _load(force: true);
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GymEvidenceList extends StatelessWidget {
  const GymEvidenceList({super.key, required this.evidence});
  final List<GymExerciseEvidence> evidence;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final names
          in evidence.map((e) => e.equipmentNames.join(' ＋ ')).toSet())
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(names),
        ),
    ],
  );
}

class GymEquipmentExercisesPage extends StatefulWidget {
  const GymEquipmentExercisesPage({
    super.key,
    required this.store,
    required this.equipment,
    this.onAdd,
    this.existingIds = const {},
    this.evidence,
    this.pending = false,
    this.allowReports = true,
  });
  final GymStore store;
  final GymEquipment equipment;
  final Future<void> Function(Set<String>)? onAdd;
  final Set<String> existingIds;
  final List<GymExerciseEvidence>? evidence;
  final bool pending;
  final bool allowReports;
  @override
  State<GymEquipmentExercisesPage> createState() =>
      _GymEquipmentExercisesPageState();
}

class _GymEquipmentExercisesPageState extends State<GymEquipmentExercisesPage> {
  bool _busy = false;
  late bool _pending = widget.pending;
  late final Set<String> _added = {...widget.existingIds};
  final Set<String> _selected = {};
  List<GymExerciseEvidence> get _evidence =>
      widget.evidence ??
      [
        if (widget.equipment.usable)
          for (final id in widget.equipment.exerciseIds)
            GymExerciseEvidence(
              id,
              [widget.equipment.id],
              [widget.equipment.name],
            ),
      ];
  Future<void> _add() async {
    if (_busy || _selected.isEmpty) return;
    setState(() => _busy = true);
    final ids = {..._selected};
    try {
      await widget.onAdd!(ids);
      if (mounted) {
        setState(() {
          _added.addAll(ids);
          _selected.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('種目を追加できませんでした。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forms = availableForms(_evidence.map((e) => e.exerciseId)).toList()
      ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
    final combos = _evidence.where((e) => e.ruleId != null).toList();
    final checked = widget.equipment.checkedAt?.toLocal();
    return Scaffold(
      appBar: AppBar(title: Text(widget.equipment.name, maxLines: 2)),
      bottomNavigationBar: widget.onAdd == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('addSelectedGymExercises'),
                  onPressed: _busy || _selected.isEmpty ? null : _add,
                  child: Text('${_selected.length}種目を追加'),
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.store.displayName),
            if (widget.equipment.manufacturer != null)
              Text('メーカー：${widget.equipment.manufacturer}'),
            if (widget.equipment.model != null)
              Text('型番：${widget.equipment.model}'),
            if (checked != null)
              Text('最終確認日：${checked.year}/${checked.month}/${checked.day}'),
            if (!widget.equipment.usable) const Text('一時利用不可'),
            if (_pending) const Text('確認中', key: Key('gymReportPending')),
            const SizedBox(height: 16),
            const Text(
              'この設備でできる種目',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (combos.isNotEmpty) ...[
              const Text('他の設備と組み合わせてできる種目'),
              GymEvidenceList(evidence: combos),
            ],
            if (forms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('対応種目は現在準備中です'),
              ),
            for (final f in forms)
              Card(
                child: ListTile(
                  key: ValueKey('addGymExercise${f.exerciseId}'),
                  selected: _selected.contains(f.exerciseId),
                  selectedTileColor: AppColors.primaryGreenSoft,
                  title: Text(f.exerciseName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _added.contains(f.exerciseId)
                            ? '追加済み'
                            : '${f.category} ・ ${f.equipmentLabel}',
                      ),
                      GymEvidenceList(
                        evidence: _evidence
                            .where(
                              (e) =>
                                  ExerciseFormCatalog.canonicalDefinition(
                                    e.exerciseId,
                                  )?.exerciseId ==
                                  f.exerciseId,
                            )
                            .toList(),
                      ),
                    ],
                  ),
                  trailing:
                      _added.contains(f.exerciseId) ||
                          _selected.contains(f.exerciseId)
                      ? const Icon(Icons.check)
                      : null,
                  onTap:
                      widget.onAdd == null ||
                          _busy ||
                          _added.contains(f.exerciseId)
                      ? null
                      : () => setState(() {
                          if (!_selected.add(f.exerciseId)) {
                            _selected.remove(f.exerciseId);
                          }
                        }),
                ),
              ),
            const SizedBox(height: 20),
            if (widget.allowReports)
              OutlinedButton.icon(
                key: const Key('reportGymEquipment'),
                onPressed: () async {
                  final sent = await showGymEquipmentReport(
                    context,
                    widget.store,
                    widget.equipment,
                  );
                  if (sent && mounted) {
                    try {
                      final pending = await GymServices.repository
                          .pendingEquipment(widget.store.id);
                      if (mounted) {
                        setState(
                          () =>
                              _pending = pending.contains(widget.equipment.id),
                        );
                      }
                    } catch (_) {
                      if (mounted) setState(() => _pending = true);
                    }
                  }
                },
                icon: const Icon(Icons.outlined_flag),
                label: const Text('設備情報の誤りを報告'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showGymEquipmentReport(
  BuildContext context,
  GymStore store,
  GymEquipment? equipment,
) async {
  final repo = GymServices.repository;
  if (!repo.canReport) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ログインが必要です'),
        content: const Text('マイページのアカウントからログインすると設備情報を報告できます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
    return false;
  }
  if (context.mounted) {
    return await showDialog<bool>(
          context: context,
          builder: (_) =>
              _ReportDialog(store: store, equipment: equipment, repo: repo),
        ) ??
        false;
  }
  return false;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.store,
    required this.equipment,
    required this.repo,
  });
  final GymStore store;
  final GymEquipment? equipment;
  final GymRepository repo;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late String _kind = widget.equipment == null ? 'added' : 'not_present';
  final _name = TextEditingController(), _comment = TextEditingController();
  final _quantity = TextEditingController(),
      _unavailableQuantity = TextEditingController();
  String _unavailableScope = 'all';
  bool _onSiteConfirmed = false;
  String? _selectedEquipment;
  bool _busy = false;
  String? _error;
  static const _kinds = {
    'not_present': '設置されていない',
    'removed': '撤去された',
    'added': '現地で確認した設備を登録',
    'quantity_changed': '台数が違う',
    'temporarily_unavailable': '現在利用できない',
    'available_again': '利用可能に戻った',
    'wrong_name': '名称が違う',
    'other': 'その他',
  };
  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _quantity.dispose();
    _unavailableQuantity.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_kind == 'added' && _name.text.trim().isEmpty) {
      setState(() => _error = '追加された設備名を入力してください');
      return;
    }
    if (_kind == 'added' &&
        widget.store.communityEquipmentOnly &&
        !_onSiteConfirmed) {
      setState(() => _error = '店舗で実際に確認した設備のみ登録できます');
      return;
    }
    final quantity = int.tryParse(_quantity.text.trim());
    final unavailableQuantity = int.tryParse(_unavailableQuantity.text.trim());
    if (_kind == 'quantity_changed' &&
        (quantity == null || quantity < 1 || quantity > 100)) {
      setState(() => _error = '現在の総台数を1〜100で入力してください');
      return;
    }
    if (_kind == 'temporarily_unavailable' &&
        _unavailableScope == 'partial' &&
        (unavailableQuantity == null ||
            unavailableQuantity < 1 ||
            unavailableQuantity >= (widget.equipment?.quantity ?? 0))) {
      setState(() => _error = '利用不可台数を、総台数より少ない数で入力してください');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.report(
        storeId: widget.store.id,
        equipmentId: _kind == 'added' ? null : widget.equipment?.id,
        kind: _kind,
        equipmentName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        comment: _kind == 'added' && widget.store.communityEquipmentOnly
            ? '[現地確認]${_comment.text}'
            : _comment.text,
        reportedQuantity: _kind == 'quantity_changed' ? quantity : null,
        unavailableScope: _kind == 'temporarily_unavailable'
            ? _unavailableScope
            : null,
        reportedUnavailableQuantity:
            _kind == 'temporarily_unavailable' && _unavailableScope == 'partial'
            ? unavailableQuantity
            : null,
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('報告を受け付けました。設備情報を確認・更新します。')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '送信できませんでした。連続送信は制限されています。時間をおいて再度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('設備情報を報告'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('gymReportKind'),
              initialValue: _kind,
              isExpanded: true,
              items: [
                for (final entry in _kinds.entries)
                  if (widget.equipment != null ||
                      !{
                        'quantity_changed',
                        'temporarily_unavailable',
                        'available_again',
                      }.contains(entry.key))
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _kind = v!),
            ),
            if (_kind == 'added') ...[
              DropdownButtonFormField<String>(
                key: const Key('gymReportEquipmentChoice'),
                initialValue: _selectedEquipment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '設備を選択'),
                items: [
                  for (final name in const [
                    'チェストプレス',
                    'ラットプルダウン',
                    'レッグプレス',
                    'レッグカール',
                    'レッグエクステンション',
                    'スミスマシン',
                    'パワーラック',
                    'ダンベル',
                    'ベンチ',
                    'トレッドミル',
                    'その他',
                  ])
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _selectedEquipment = value;
                        _name.text = value == 'その他' ? '' : value ?? '';
                      }),
              ),
              if (widget.store.communityEquipmentOnly)
                CheckboxListTile(
                  key: const Key('gymReportOnSiteConfirmed'),
                  value: _onSiteConfirmed,
                  title: const Text('この店舗で実際に設備を確認しました'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _onSiteConfirmed = value == true),
                ),
            ],
            if (_kind == 'added' || _kind == 'wrong_name')
              TextField(
                key: const Key('gymReportEquipmentName'),
                controller: _name,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: _kind == 'added' ? '設備名（必須）' : '正しい設備名（任意）',
                ),
              ),
            if (_kind == 'quantity_changed')
              TextField(
                key: const Key('gymReportedQuantity'),
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '現在の総台数（必須）',
                  hintText: '例：3台',
                ),
              ),
            if (_kind == 'temporarily_unavailable') ...[
              DropdownButtonFormField<String>(
                key: const Key('gymUnavailableScope'),
                initialValue: _unavailableScope,
                decoration: const InputDecoration(labelText: '利用できない範囲'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全台利用不可')),
                  if ((widget.equipment?.quantity ?? 0) > 1)
                    const DropdownMenuItem(
                      value: 'partial',
                      child: Text('一部利用不可'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _unavailableScope = v!),
              ),
              if (_unavailableScope == 'partial')
                TextField(
                  key: const Key('gymReportedUnavailableQuantity'),
                  controller: _unavailableQuantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '利用不可台数（必須）',
                    helperText: widget.equipment?.quantity == null
                        ? '総台数が未登録のため、一部利用不可は報告できません'
                        : '登録総台数：${widget.equipment!.quantity}台',
                  ),
                ),
            ],
            if (_kind == 'available_again') const Text('全台が再び利用できる状態として報告します。'),
            TextField(
              key: const Key('gymReportComment'),
              controller: _comment,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'コメント（任意）'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('submitGymEquipmentReport'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? '送信中…' : '報告を送信'),
        ),
      ],
    ),
  );
}

/// Same registered-store repository as the management page; no brand-only or
/// legacy name matching. A one-workout selection never changes the default.
class TrainingPlacePicker extends StatefulWidget {
  const TrainingPlacePicker({
    super.key,
    this.currentStoreId,
    this.currentName,
    this.currentCustomPlaceId,
  });
  final String? currentStoreId, currentName, currentCustomPlaceId;
  @override
  State<TrainingPlacePicker> createState() => _TrainingPlacePickerState();
}

class _TrainingPlacePickerState extends State<TrainingPlacePicker> {
  final _repo = GymServices.repository;
  List<GymStore> _stores = [];
  bool _busy = true, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await TrainingPlacePreference.migrateKanekinPlace(_repo);
      await CustomGymPreference.load();
      final stores = await _repo.registered();
      if (mounted) setState(() => _stores = stores);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final store = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const GymStoreSearchPage()),
    );
    if (store == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final TrainingPlace place;
      if (store is GymStore) {
        await _repo.register(store);
        place = TrainingPlace.store(store);
      } else {
        place = store as TrainingPlace;
      }
      if (mounted) Navigator.pop(context, place);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('店舗を登録できませんでした。再度お試しください。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        const ListTile(
          title: Text(
            'トレーニング場所',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
        ),
        ListTile(
          key: const Key('selectTrainingPlaceHome'),
          title: const Text('自宅'),
          leading: const Icon(Icons.home_outlined),
          trailing: widget.currentStoreId == null && widget.currentName == '自宅'
              ? const Icon(Icons.check_circle_outline)
              : null,
          onTap: () => Navigator.pop(context, const TrainingPlace.home()),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_failed) gymError(_load),
        for (final store in _stores.where((s) => s.isSelectable))
          ListTile(
            key: ValueKey('selectRegisteredPlace${store.id}'),
            title: Text(store.displayName),
            leading: const Icon(Icons.location_on_outlined),
            trailing: widget.currentStoreId == store.id
                ? const Icon(Icons.check_circle_outline)
                : null,
            onTap: () => Navigator.pop(context, TrainingPlace.store(store)),
          ),
        for (final name in CustomGymPreference.gyms)
          ListTile(
            key: ValueKey('selectManualPlace$name'),
            title: Text(name),
            subtitle: const Text('手動登録'),
            leading: const Icon(Icons.place_outlined),
            trailing:
                widget.currentStoreId == null &&
                    (widget.currentCustomPlaceId != null
                        ? widget.currentCustomPlaceId ==
                              CustomGymPreference.idFor(name)
                        : widget.currentName == name)
                ? const Icon(Icons.check_circle_outline)
                : null,
            onTap: () => Navigator.pop(context, TrainingPlace.manual(name)),
          ),
        ListTile(
          key: const Key('searchRegisteredGymStores'),
          title: const Text('ジムを追加'),
          leading: const Icon(Icons.add),
          onTap: _busy ? null : _add,
        ),
      ],
    ),
  );
}
