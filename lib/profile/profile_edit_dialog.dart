import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'profile_preference.dart';

/// Cloud fields are committed together. Retain the receipt if local caching
/// fails, so retrying does not upload the same photo again.
class ProfileEditSaveCoordinator {
  ProfileEditSaveCoordinator({
    required this.saveLocalName,
    this.saveRemote,
    this.checkAccount,
  });
  final Future<void> Function(String) saveLocalName;
  final Future<void> Function(String, bool, Uint8List?)? saveRemote;
  final VoidCallback? checkAccount;
  String? remoteName;
  bool localSaveFailed = false;
  bool _photoCommitted = false;
  Uint8List? _committedPhoto;

  Future<void> save(String name, bool photoChanged, Uint8List? photo) async {
    localSaveFailed = false;
    final value = name.trim();
    checkAccount?.call();
    final needsPhoto =
        photoChanged &&
        (!_photoCommitted || !identical(photo, _committedPhoto));
    if (saveRemote != null && (remoteName != value || needsPhoto)) {
      await saveRemote!(value, needsPhoto, photo);
      remoteName = value;
      if (needsPhoto) {
        _photoCommitted = true;
        _committedPhoto = photo;
      }
    }
    checkAccount?.call();
    try {
      await saveLocalName(value);
    } catch (_) {
      localSaveFailed = true;
      rethrow;
    }
  }
}

class ProfileEditDialog extends StatefulWidget {
  const ProfileEditDialog({
    super.key,
    required this.initialName,
    required this.currentAvatar,
    required this.hasPhoto,
    required this.canEditPhoto,
    required this.pickPhoto,
    required this.saver,
  });
  final String initialName;
  final Widget currentAvatar;
  final bool hasPhoto;
  final bool canEditPhoto;
  final Future<Uint8List?> Function() pickPhoto;
  final ProfileEditSaveCoordinator saver;
  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late String _name = widget.initialName;
  Uint8List? _photo;
  bool _photoChanged = false, _saving = false, _picking = false;
  String? _error;
  bool get _busy => _saving || _picking;
  bool get _hasPhoto => _photoChanged ? _photo != null : widget.hasPhoto;
  String tr(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;

  Future<void> _pick() async {
    if (_busy || !widget.canEditPhoto) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await widget.pickPhoto();
      if (!mounted || photo == null) return;
      setState(() {
        _photo = photo;
        _photoChanged = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            '写真を読み込めませんでした。別の写真を選ぶか、再度お試しください。',
            'Could not load the photo. Choose another photo or retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.saver.save(_name, _photoChanged, _photo);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(_name.trim());
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              widget.saver.localSaveFailed && widget.saver.remoteName != null
              ? tr(
                  'クラウドの変更は保存済みですが、端末内の表示名を保存できませんでした。保存を押して再試行してください。',
                  'Cloud changes are saved, but the name could not be saved on this device. Press Save to retry.',
                )
              : tr(
                  'プロフィールを保存できませんでした。変更内容を残しています。再度お試しください。',
                  'Could not save the profile. Your edits are kept here. Please retry.',
                );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const Key('profileEditDialog'),
      scrollable: true,
      title: Text(tr('プロフィールを編集', 'Edit profile')),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: SizedBox(
                key: const Key('profilePhotoPreview'),
                width: 80,
                height: 80,
                child: !_photoChanged
                    ? widget.currentAvatar
                    : CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFC7F36B),
                        child: _photo == null
                            ? const Icon(Icons.person_rounded, size: 42)
                            : ClipOval(
                                child: Image.memory(
                                  _photo!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('pickProfilePhoto'),
                  onPressed: !_busy && widget.canEditPhoto ? _pick : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(tr('写真を変更', 'Change photo')),
                ),
                if (_hasPhoto)
                  TextButton.icon(
                    key: const Key('removeProfilePhoto'),
                    onPressed: !_busy && widget.canEditPhoto
                        ? () => setState(() {
                            _photo = null;
                            _photoChanged = true;
                            _error = null;
                          })
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr('写真を削除', 'Remove photo')),
                  ),
              ],
            ),
            if (!widget.canEditPhoto)
              Text(
                tr(
                  '写真の設定にはログインと対応したプロフィールが必要です。',
                  'Sign in with an available profile to change your photo.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            if (_picking) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('profileDisplayNameField'),
              initialValue: widget.initialName,
              enabled: !_busy,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: tr('表示名（任意）', 'Display name (optional)'),
                hintText: ProfilePreference.defaultDisplayName,
              ),
              onChanged: (text) => _name = text,
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null)
              Text(
                _error!,
                key: const Key('profileEditError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            widget.saver.remoteName == null
                ? tr('キャンセル', 'Cancel')
                : tr('閉じる', 'Close'),
          ),
        ),
        FilledButton(
          key: const Key('saveProfileDisplayName'),
          onPressed: _busy ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('保存', 'Save')),
        ),
      ],
    ),
  );
}
