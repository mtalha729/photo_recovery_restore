import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/app/design_system/theme/app_theme.dart';
import 'package:photo_recovery_restore/features/recovery/data/deep_storage/deep_storage_recovery_provider.dart';
import 'package:photo_recovery_restore/features/recovery_scan/presentation/photo_recovery_access_screen.dart';

void main() {
  const channel = MethodChannel(
    'com.photorecoveryrestore.app/deep_storage_recovery',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('uses truthful Photo Recovery Access wording', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAccessScreen(
          provider: const PlatformDeepStorageRecoveryProvider.withChannel(
            channel,
          ),
          onAccessAvailable: () {},
        ),
      ),
    );

    expect(find.text('Photo Recovery Access'), findsNWidgets(2));
    expect(find.text('Enable Photo Recovery Access'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.textContaining('All files access'), findsNothing);
  });

  testWidgets('Not now does not open Android special access settings', (
    tester,
  ) async {
    var settingsRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'openDeepStorageAccessSettings') {
            settingsRequests++;
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PhotoRecoveryAccessScreen(
          provider: const PlatformDeepStorageRecoveryProvider.withChannel(
            channel,
          ),
          onAccessAvailable: () {},
        ),
      ),
    );

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(settingsRequests, 0);
  });
}
