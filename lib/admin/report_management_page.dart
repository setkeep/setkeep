import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'report_repository.dart';
import 'official_source_page.dart';
import 'official_source_repository.dart';
import '../gym/gym_repository.dart';
import '../gym/gym_pages.dart';

/// Visibility is only a convenience; every read/write is authorized by the DB.
class ReportAdminEntry extends StatefulWidget {
  const ReportAdminEntry({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ReportAdminEntry> createState() => _ReportAdminEntryState();
}

class _ReportAdminEntryState extends State<ReportAdminEntry> {
  final repo = ReportServices.repository;
  StreamSubscription<void>? subscription;
  bool admin = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    refresh();
    subscription = repo.authChanges.listen((_) {
      refresh();
    });
  }

  Future<void> refresh() async {
    final version = ++request;
    if (mounted) setState(() => admin = false);
    try {
      final allowed = await repo.isAdmin();
      if (mounted && version == request) setState(() => admin = allowed);
    } catch (_) {
      /* Fail closed. */
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!admin) return const SizedBox.shrink();
    final tile = ListTile(
      key: const Key('reportAdminEntry'),
      leading: const Icon(Icons.admin_panel_settings_outlined),
      title: const Text('報告管理'),
      subtitle: const Text('管理者専用'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const ReportManagementPage()),
        );
        refresh();
      },
    );
    return widget.embedded
        ? Column(children: [const Divider(height: 1, thickness: 0.5), tile])
        : Card(child: tile);
  }
}

class ReportManagementPage extends StatefulWidget {
  const ReportManagementPage({super.key});
  @override
  State<ReportManagementPage> createState() => _ReportManagementPageState();
}

class _ReportManagementPageState extends State<ReportManagementPage> {
  final repo = ReportServices.repository;
  final search = TextEditingController();
  StreamSubscription<void>? subscription;
  Timer? debounce;
  String type = 'exercise';
  String? status = 'pending', error;
  List<AdminReport> rows = [];
  List<AdminCandidate> candidates = [];
  Map<String, int> counts = {};
  bool busy = true, admin = false, more = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
    subscription = repo.authChanges.listen((_) {
      setState(() => admin = false);
      load();
    });
  }

  Future<void> load({bool append = false}) async {
    final version = ++request;
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        rows = [];
        candidates = [];
        counts = {};
      }
    });
    try {
      final allowed = await repo.isAdmin();
      if (!mounted || version != request) return;
      if (!allowed) {
        setState(() {
          admin = false;
          busy = false;
          rows = [];
          candidates = [];
        });
        return;
      }
      if (type == 'candidate' || type == 'store') {
        final batch = await repo.listCandidates(
          append ? candidates.length : 0,
          entityType: type == 'store' ? 'store' : 'store_equipment',
        );
        if (!mounted || version != request) return;
        setState(() {
          admin = true;
          candidates = append ? [...candidates, ...batch] : batch;
          more = batch.length == 50;
          busy = false;
        });
        return;
      }
      final batch = await repo.list(
        type,
        status,
        search.text,
        append ? rows.length : 0,
      );
      if (!mounted || version != request) return;
      setState(() {
        admin = true;
        rows = append ? [...rows, ...batch.rows] : batch.rows;
        counts = batch.counts;
        more = batch.rows.length == 50;
        busy = false;
      });
    } catch (_) {
      if (mounted && version == request) {
        setState(() {
          busy = false;
          error = '報告を取得できませんでした。再度お試しください。';
        });
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    subscription?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('報告管理'),
      actions: [
        if (admin)
          IconButton(
            tooltip: '公式情報の取得状況',
            icon: const Icon(Icons.public),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const OfficialSourcePage()),
            ),
          ),
        IconButton(
          onPressed: busy ? null : () => load(),
          icon: const Icon(Icons.refresh),
          tooltip: '再読み込み',
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          if (!busy && error == null && !admin)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('管理者のみ利用できます'),
            ),
          if (admin) ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'exercise', label: Text('対応種目')),
                    ButtonSegment(value: 'equipment', label: Text('設備情報')),
                    ButtonSegment(value: 'candidate', label: Text('変更候補')),
                    ButtonSegment(value: 'store', label: Text('店舗情報')),
                  ],
                  selected: {type},
                  onSelectionChanged: busy
                      ? null
                      : (v) {
                          type = v.single;
                          load();
                        },
                ),
              ),
            ),
            if (type == 'candidate' || type == 'store')
              Expanded(
                child: candidates.isEmpty
                    ? const Center(child: Text('変更候補はありません'))
                    : ListView.builder(
                        itemCount: candidates.length + (more ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == candidates.length) {
                            return TextButton(
                              onPressed: busy ? null : () => load(append: true),
                              child: const Text('さらに表示'),
                            );
                          }
                          final candidate = candidates[index];
                          return ListTile(
                            key: ValueKey('adminCandidate${candidate.id}'),
                            title: Text(
                              '${candidate.storeName}\n${candidate.changeLabel} ・ ${candidate.targetName}',
                            ),
                            subtitle: Text(
                              '${candidate.statusLabel}  支持 ${candidate.supportScore} / 反対 ${candidate.opposeScore}  報告者 ${candidate.uniqueReporters}人\n'
                              '${candidate.stateSummary == null ? '' : '${candidate.stateSummary}\n'}'
                              '根拠 ${candidate.data['evidence_count'] ?? 0}件 ・ 初回 ${candidate.dateLabel('first_seen_at')}  最終 ${candidate.dateLabel('last_seen_at')}',
                            ),
                            isThreeLine: true,
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _CandidateDetail(
                                    candidate: candidate,
                                    repo: repo,
                                  ),
                                ),
                              );
                              if (mounted) load();
                            },
                          );
                        },
                      ),
              ),
            if (type != 'candidate' && type != 'store') ...[
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final entry in {
                      ...reportStatuses,
                      'all': 'すべて',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          key: ValueKey('reportStatus${entry.key}'),
                          label: Text(
                            '${entry.value} ${entry.key == 'all' ? counts.values.fold(0, (a, b) => a + b) : counts[entry.key] ?? 0}',
                          ),
                          selected: (status ?? 'all') == entry.key,
                          onSelected: busy
                              ? null
                              : (_) {
                                  status = entry.key == 'all'
                                      ? null
                                      : entry.key;
                                  load();
                                },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: search,
                  key: const Key('reportAdminSearch'),
                  decoration: const InputDecoration(
                    labelText: '店舗名・種目名・設備名で検索',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) {
                    debounce?.cancel();
                    debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => load(),
                    );
                  },
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('報告はありません'))
                    : ListView.builder(
                        itemCount: rows.length + (more ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == rows.length) {
                            return TextButton(
                              onPressed: busy ? null : () => load(append: true),
                              child: const Text('さらに表示'),
                            );
                          }
                          final r = rows[index];
                          return ListTile(
                            key: ValueKey('adminReport${r.id}'),
                            title: Text('${r.storeName}\n${r.targetName}'),
                            subtitle: Text(
                              '${r.kindLabel}\n${r.data['comment']}\n${r.dateLabel} ・ ${reportStatuses[r.status]}',
                            ),
                            isThreeLine: true,
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _ReportDetail(report: r, repo: repo),
                                ),
                              );
                              if (mounted) load();
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

class _CandidateDetail extends StatefulWidget {
  const _CandidateDetail({required this.candidate, required this.repo});
  final AdminCandidate candidate;
  final ReportRepository repo;

  @override
  State<_CandidateDetail> createState() => _CandidateDetailState();
}

class _CandidateDetailState extends State<_CandidateDetail> {
  bool busy = false;
  String? error;
  final rollbackReason = TextEditingController();
  late final evidence = widget.repo.candidateEvidence(widget.candidate.id);

  @override
  void dispose() {
    rollbackReason.dispose();
    super.dispose();
  }

  Future<void> _rollback() async {
    if (busy) return;
    rollbackReason.clear();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('この変更を元に戻しますか？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('反映前の状態に戻します。現在の状態が別途変更されている場合は実行できません。'),
              TextField(
                key: const Key('candidateRollbackReason'),
                controller: rollbackReason,
                maxLength: 1000,
                onChanged: (_) => refresh(() {}),
                decoration: const InputDecoration(labelText: '理由（必須）'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('confirmCandidateRollback'),
              onPressed: rollbackReason.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, rollbackReason.text.trim()),
              child: const Text('元に戻す'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repo.rollbackCandidate(widget.candidate.id, reason);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = '変更を元に戻せませんでした。最新の状態を確認してください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(String action) async {
    final note = rollbackReason;
    note.clear();
    final answer = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(
            action == 'apply'
                ? '確認した店舗状態を反映しますか？'
                : action == 'reject'
                ? 'この報告を却下しますか？'
                : '確認を開始',
          ),
          content: TextField(
            key: const Key('storeCandidateNote'),
            controller: note,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: action == 'reviewing' ? '管理者メモ' : '確認根拠・理由（必須）',
            ),
            onChanged: (_) => refresh(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('confirmStoreCandidate'),
              onPressed: action != 'reviewing' && note.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, note.text.trim()),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
    if (answer == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repo.reviewStoreCandidate(
        widget.candidate.id,
        action,
        answer,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '更新できませんでした。最新の状態と権限を確認してください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    const encoder = JsonEncoder.withIndent('  ');
    return Scaffold(
      appBar: AppBar(title: const Text('変更候補の詳細')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(c.storeName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${c.changeLabel} ・ ${c.targetName}'),
            if (c.stateSummary != null) Text(c.stateSummary!),
            Text('状態：${c.statusLabel}'),
            Text(
              '支持 ${c.supportScore} / 反対 ${c.opposeScore} ・ 報告者 ${c.uniqueReporters}人',
            ),
            Text('初回 ${c.dateLabel('first_seen_at')}'),
            Text('最終 ${c.dateLabel('last_seen_at')}'),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: evidence,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('根拠を取得できませんでした。');
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in snapshot.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e['source_type'] == 'official'
                              ? '公式サイト確認'
                              : e['source_type'] == 'training_confirmation'
                              ? 'トレーニング後の設備確認'
                              : '報告・確認情報',
                        ),
                        subtitle: Text(
                          '${e['direction'] == 'oppose' ? '反対' : '支持'} ・ ${officialDate(e['observed_at'])}\n${e['source_url'] ?? ''}\n${encoder.convert(e['data'])}',
                        ),
                      ),
                  ],
                );
              },
            ),
            if (c.isStore) ...[
              Text('判定理由: ${c.data['decision_reason'] ?? '未評価'}'),
              Text('根拠: ${c.data['evidence_count'] ?? 0}件'),
              const Text('変更提案・既存店舗の可能性'),
              SelectableText(encoder.convert(c.proposedValue)),
              if ([
                'collecting',
                'needs_review',
                'auto_ready',
              ].contains(c.status)) ...[
                TextButton(
                  key: const Key('reviewStoreCandidate'),
                  onPressed: busy ? null : () => review('reviewing'),
                  child: const Text('確認を開始'),
                ),
                if ([
                  'store_closed',
                  'store_temporarily_closed',
                  'store_reopened',
                ].contains(c.changeType))
                  FilledButton(
                    key: const Key('applyStoreCandidate'),
                    onPressed: busy ? null : () => review('apply'),
                    child: const Text('確認した店舗状態を反映'),
                  ),
                TextButton(
                  key: const Key('rejectStoreCandidate'),
                  onPressed: busy ? null : () => review('reject'),
                  child: const Text('却下'),
                ),
              ],
            ],
            if (c.appliedAt != null) Text('反映日時 ${c.dateLabel('applied_at')}'),
            if (c.afterData != null) ...[
              const SizedBox(height: 16),
              Text('変更前', style: Theme.of(context).textTheme.titleMedium),
              SelectableText(
                c.beforeData == null
                    ? 'この店舗に設備登録なし'
                    : encoder.convert(c.beforeData),
              ),
              const SizedBox(height: 12),
              Text('変更後', style: Theme.of(context).textTheme.titleMedium),
              SelectableText(encoder.convert(c.afterData)),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.status == 'auto_applied' ||
                (c.isStore && c.status == 'admin_applied')) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('rollbackCandidate'),
                onPressed: busy ? null : _rollback,
                icon: const Icon(Icons.undo),
                label: const Text('この変更を元に戻す'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportDetail extends StatefulWidget {
  const _ReportDetail({required this.report, required this.repo});
  final AdminReport report;
  final ReportRepository repo;
  @override
  State<_ReportDetail> createState() => _ReportDetailState();
}

class _ReportDetailState extends State<_ReportDetail> {
  late final note = TextEditingController(text: widget.report.note);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> update(String status) async {
    if (busy) return;
    if (status == 'rejected' && note.text.trim().isEmpty) {
      setState(() => error = '却下理由を管理者メモに入力してください');
      return;
    }
    if (status == 'applied' || status == 'rejected') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('この報告を${reportStatuses[status]}にしますか？'),
          content: const Text('設備・対応種目のマスターは変更されません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const Key('confirmReportReview'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repo.update(widget.report, status, note.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '更新できませんでした。権限または最新の状態を確認して再度お試しください。';
        });
      }
    }
  }

  Future<void> openStore() async {
    setState(() => busy = true);
    try {
      final store = await GymServices.repository.storeById(
        widget.report.storeId,
      );
      if (!mounted) return;
      if (store == null) throw StateError('Store unavailable');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => GymStoreEquipmentPage(store: store)),
      );
    } catch (_) {
      if (mounted) setState(() => error = '店舗情報を取得できませんでした');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(title: const Text('報告詳細')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(r.storeName, style: Theme.of(context).textTheme.titleLarge),
            Text('店舗ID: ${r.storeId}'),
            TextButton(
              onPressed: busy ? null : openStore,
              child: const Text('店舗情報を見る'),
            ),
            Text(r.targetName, style: Theme.of(context).textTheme.titleMedium),
            Text('種目・設備ID: ${r.data['target_id'] ?? '指定なし'}'),
            if (r.data['entered_name'] != null)
              Text('ユーザー入力設備名: ${r.data['entered_name']}'),
            Text('報告種類: ${r.kindLabel}'),
            Text('コメント: ${r.data['comment']}'),
            Text('報告日時: ${r.dateLabel}'),
            Text('状態: ${reportStatuses[r.status]}'),
            if (r.data['reviewed_at'] != null)
              Text('最終確認: ${r.data['reviewed_at']}'),
            TextField(
              key: const Key('reportAdminNote'),
              controller: note,
              enabled: !busy,
              maxLines: 4,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: '管理者メモ（却下時は必須）'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (r.status == 'pending')
              FilledButton(
                key: const Key('startReportReview'),
                onPressed: busy ? null : () => update('reviewing'),
                child: const Text('確認を開始'),
              ),
            if (r.status == 'reviewing')
              FilledButton(
                key: const Key('applyReportReview'),
                onPressed: busy ? null : () => update('applied'),
                child: const Text('反映済みにする'),
              ),
            if (r.status == 'pending' || r.status == 'reviewing')
              TextButton(
                key: const Key('rejectReportReview'),
                onPressed: busy ? null : () => update('rejected'),
                child: const Text('却下'),
              ),
            OutlinedButton(
              onPressed: busy ? null : () => update(r.status),
              child: const Text('メモを保存'),
            ),
          ],
        ),
      ),
    );
  }
}
