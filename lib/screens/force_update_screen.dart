import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version_policy.dart';
import '../widgets/app_logo.dart';

class ForceUpdateScreen extends StatelessWidget {
  final AppVersionPolicy policy;
  final int installedVersionCode;
  final bool fromCachedPolicy;

  const ForceUpdateScreen({
    super.key,
    required this.policy,
    required this.installedVersionCode,
    this.fromCachedPolicy = false,
  });

  Future<void> _openStore(BuildContext context) async {
    final url = Uri.tryParse(policy.playStoreUrl);
    if (url == null) {
      _showMessage(context, 'Play Store link is not available.');
      return;
    }
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showMessage(context, 'Unable to open Play Store.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1F3A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const AppLogo(size: 128, fit: BoxFit.contain),
                const SizedBox(height: 28),
                const Text(
                  'Update Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  fromCachedPolicy
                      ? 'A required app update was detected earlier. Please connect to internet and update the app to continue.'
                      : 'A new RPF WCR app version is available. Please update from Play Store to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _VersionLine(
                  installedVersionCode: installedVersionCode,
                  requiredVersionCode: policy.minimumVersionCode,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _openStore(context),
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('Update Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF0B1F3A),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'App cannot be used until this update is installed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  final int installedVersionCode;
  final int requiredVersionCode;

  const _VersionLine({
    required this.installedVersionCode,
    required this.requiredVersionCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        'Installed: $installedVersionCode  |  Required: $requiredVersionCode',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
