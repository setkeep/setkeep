import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/profile/profile_edit_dialog.dart';

void main() {
  test('local failure retries without resending committed photo', () async {
    var remote = 0, local = 0;
    final photo = Uint8List.fromList([1]);
    final saver = ProfileEditSaveCoordinator(
      saveRemote: (name, changed, bytes) async {
        remote++;
        expect(changed, true);
        expect(bytes, same(photo));
      },
      saveLocalName: (_) async {
        if (++local == 1) throw StateError('disk');
      },
    );
    await expectLater(saver.save(' Name ', true, photo), throwsStateError);
    await saver.save('Name', true, photo);
    expect(remote, 1);
    expect(local, 2);
  });
  test('remote failure leaves local name untouched', () async {
    var local = 0;
    final saver = ProfileEditSaveCoordinator(
      saveRemote: (_, _, _) async => throw StateError('network'),
      saveLocalName: (_) async {
        local++;
      },
    );
    await expectLater(saver.save('Name', true, null), throwsStateError);
    expect(local, 0);
    expect(saver.remoteName, null);
  });
  test('account switch after cloud save prevents local write', () async {
    var switched = false, local = 0;
    final saver = ProfileEditSaveCoordinator(
      checkAccount: () {
        if (switched) throw StateError('account');
      },
      saveRemote: (_, _, _) async {
        switched = true;
      },
      saveLocalName: (_) async {
        local++;
      },
    );
    await expectLater(saver.save('Name', false, null), throwsStateError);
    expect(local, 0);
  });
  Future<void> open(
    WidgetTester tester,
    ProfileEditSaveCoordinator saver, {
    Future<Uint8List?> Function()? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ProfileEditDialog(
                  initialName: 'Before',
                  currentAvatar: const CircleAvatar(child: Icon(Icons.person)),
                  hasPhoto: true,
                  canEditPhoto: true,
                  pickPhoto: picker ?? () async => null,
                  saver: saver,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel discards name and removal without writes', (
    tester,
  ) async {
    var writes = 0;
    await open(
      tester,
      ProfileEditSaveCoordinator(
        saveLocalName: (_) async {
          writes++;
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      'After',
    );
    await tester.tap(find.byKey(const Key('removeProfilePhoto')));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byKey(const Key('profileEditDialog')), findsNothing);
  });
  testWidgets('picker cancellation preserves current photo', (tester) async {
    await open(tester, ProfileEditSaveCoordinator(saveLocalName: (_) async {}));
    await tester.tap(find.byKey(const Key('pickProfilePhoto')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('removeProfilePhoto')), findsOneWidget);
    expect(find.byKey(const Key('profileEditError')), findsNothing);
  });
  testWidgets('save is single flight and blocks back until complete', (
    tester,
  ) async {
    var writes = 0;
    final pending = Completer<void>();
    await open(
      tester,
      ProfileEditSaveCoordinator(
        saveLocalName: (_) async {
          writes++;
          await pending.future;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(writes, 1);
    expect(find.byKey(const Key('profileEditDialog')), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileEditDialog')), findsNothing);
  });
  testWidgets('failed save retains edits and allows retry', (tester) async {
    var writes = 0;
    await open(
      tester,
      ProfileEditSaveCoordinator(
        saveLocalName: (_) async {
          if (++writes == 1) throw StateError('disk');
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      'After',
    );
    await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
    await tester.pumpAndSettle();
    expect(find.text('After'), findsOneWidget);
    expect(find.byKey(const Key('profileEditError')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
    await tester.pumpAndSettle();
    expect(writes, 2);
  });
  testWidgets('small screen with keyboard keeps save accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await open(tester, ProfileEditSaveCoordinator(saveLocalName: (_) async {}));
    await tester.enterText(
      find.byKey(const Key('profileDisplayNameField')),
      'Small',
    );
    await tester.ensureVisible(find.byKey(const Key('saveProfileDisplayName')));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('saveProfileDisplayName')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileEditDialog')), findsNothing);
  });
}
