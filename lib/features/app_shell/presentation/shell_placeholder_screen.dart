import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../recovery_sources/presentation/recovery_source_intent.dart';

class ShellPlaceholderScreen extends StatelessWidget {
  const ShellPlaceholderScreen({
    required this.title,
    required this.message,
    required this.icon,
    this.embedded = false,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!embedded)
              Align(
                alignment: Alignment.centerLeft,
                child: AccessibleIconAction(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            const Spacer(),
            AppEmptyState(icon: icon, title: title, message: message),
            const Spacer(),
          ],
        ),
      ),
    );
    return embedded ? content : Scaffold(body: content);
  }
}

class RecoveryCapabilityPlaceholder extends StatelessWidget {
  const RecoveryCapabilityPlaceholder({required this.intent, super.key});

  final RecoverySourceIntent intent;

  @override
  Widget build(BuildContext context) => ShellPlaceholderScreen(
    title: intent.title,
    message: intent.capabilityMessage,
    icon: intent.icon,
  );
}
