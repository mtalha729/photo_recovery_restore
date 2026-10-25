import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/scoped_storage_recovery/storage_scope_models.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/folder_scope_selector.dart';
import 'package:photo_recovery_restore/features/recovery/data/folder_scope/platform_folder_scope_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/folder-scope');
  const selector = PlatformFolderScopeSelector.withChannel(channel);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps a persisted SAF selection without raw paths', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'selectFolder');
          return {
            'status': 'selected',
            'treeUri': 'content://com.android.externalstorage.documents/tree/1234-5678%3APictures',
            'documentId': '1234-5678:Pictures',
            'volumeName': '1234-5678',
            'isRemovable': true,
            'relativePath': 'Pictures',
          };
        });

    final result = await selector.selectFolder();

    expect(result.status, FolderScopeSelectionStatus.selected);
    expect(result.scope?.volume?.isRemovable, isTrue);
    expect(result.scope?.relativePathPrefix, 'Pictures');
    expect(result.scope?.treeUri.scheme, 'content');
  });

  test('restore destination selection uses the dedicated SAF intent', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'selectDestinationFolder');
          return {
            'status': 'selected',
            'treeUri': 'content://provider/tree/restore-target',
            'documentId': 'primary:Pictures/Recovery',
          };
        });

    final result = await selector.selectDestinationFolder();

    expect(result.status, FolderScopeSelectionStatus.selected);
    expect(result.scope?.treeUri, Uri.parse('content://provider/tree/restore-target'));
  });

  test('selected scope keeps unknown volume identity unknown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'selected',
            'treeUri': 'content://provider/tree/folder',
            'documentId': 'provider:folder',
          },
        );

    final result = await selector.selectFolder();

    expect(result.status, FolderScopeSelectionStatus.selected);
    expect(result.scope?.volume, isNull);
  });

  test('restricted Android location is represented safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'status': 'restrictedLocation',
            'message': 'Android does not permit this folder scope.',
          },
        );

    final result = await selector.selectFolder();

    expect(result.status, FolderScopeSelectionStatus.restrictedLocation);
    expect(result.scope, isNull);
  });

  test('cancelled selection is not an access or deletion result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'cancelled'},
        );

    final result = await selector.selectFolder();

    expect(result.status, FolderScopeSelectionStatus.cancelled);
    expect(result.scope, isNull);
  });

  test('grant check passes only the persisted content URI', () async {
    final scope = AuthorizedFolderScope(
      treeUri: Uri.parse('content://provider/tree/folder'),
      grantState: FolderGrantState.active,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'checkFolderGrant');
          expect(call.arguments, {'treeUri': scope.treeUri.toString()});
          return {'status': 'permissionGrantLost'};
        });

    final result = await selector.checkGrant(scope);

    expect(result.status, FolderScopeSelectionStatus.permissionGrantLost);
  });

  test('malformed selected response becomes platform failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'status': 'selected', 'treeUri': 'not a uri'},
        );

    final result = await selector.selectFolder();

    expect(result.status, FolderScopeSelectionStatus.platformFailure);
    expect(result.scope, isNull);
  });
}
