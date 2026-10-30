import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/models.dart';
import '../../config/app_config.dart';
import '../../services/platform/platform_services.dart';
import '../clock/clock_notifier.dart';
import '../history/shifts_notifier.dart';
import 'settings_notifier.dart';
import 'version_check_provider.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenController;
  late final TextEditingController _adminTokenController;
  bool _obscureToken = true;
  bool _obscureAdminToken = true;
  bool _isSaving = false;
  String _environment = 'production';

  String _prodToken = '';
  String _prodAdminToken = '';
  int _prodReminderMinutes = 0;
  bool _prodVibrationsEnabled = true;

  String _stagingToken = '';
  String _stagingAdminToken = '';
  int _stagingReminderMinutes = 0;
  bool _stagingVibrationsEnabled = true;

  int get _currentReminderMinutes =>
      _environment == 'staging' ? _stagingReminderMinutes : _prodReminderMinutes;
  set _currentReminderMinutes(int val) {
    if (_environment == 'staging') {
      _stagingReminderMinutes = val;
    } else {
      _prodReminderMinutes = val;
    }
  }

  bool get _currentVibrationsEnabled =>
      _environment == 'staging' ? _stagingVibrationsEnabled : _prodVibrationsEnabled;
  set _currentVibrationsEnabled(bool val) {
    if (_environment == 'staging') {
      _stagingVibrationsEnabled = val;
    } else {
      _prodVibrationsEnabled = val;
    }
  }

  @override
  void initState() {
    super.initState();
    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.value;

    _environment =
        (settings?.environment == 'staging') ? 'staging' : 'production';

    _prodToken = settings?.prodToken ?? '';
    _prodAdminToken = settings?.prodAdminToken ?? settings?.adminToken ?? '';
    _prodReminderMinutes =
        settings?.prodReminderMinutes ?? settings?.shiftReminderMinutes ?? 0;
    _prodVibrationsEnabled =
        settings?.prodVibrationsEnabled ?? settings?.vibrationsEnabled ?? true;

    _stagingToken = settings?.stagingToken ?? '';
    _stagingAdminToken = settings?.stagingAdminToken ?? '';
    _stagingReminderMinutes = settings?.stagingReminderMinutes ?? 0;
    _stagingVibrationsEnabled = settings?.stagingVibrationsEnabled ?? true;

    final initialToken =
        _environment == 'staging' ? _stagingToken : _prodToken;
    final initialAdminToken =
        _environment == 'staging' ? _stagingAdminToken : _prodAdminToken;

    _tokenController = TextEditingController(text: initialToken);
    _adminTokenController = TextEditingController(text: initialAdminToken);
  }

  void _switchEnvironment(String targetEnv) {
    if (_environment == targetEnv) return;

    if (_environment == 'production') {
      _prodToken = _tokenController.text.trim();
      _prodAdminToken = _adminTokenController.text.trim();
    } else {
      _stagingToken = _tokenController.text.trim();
      _stagingAdminToken = _adminTokenController.text.trim();
    }

    setState(() {
      _environment = targetEnv;
      if (targetEnv == 'production') {
        _tokenController.text = _prodToken;
        _adminTokenController.text = _prodAdminToken;
      } else {
        _tokenController.text = _stagingToken;
        _adminTokenController.text = _stagingAdminToken;
      }
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _adminTokenController.dispose();
    super.dispose();
  }

  Future<void> _pasteTo(TextEditingController controller) async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        controller.text = data.text!.trim();
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final currentToken = _tokenController.text.trim();
      final currentAdminToken = _adminTokenController.text.trim();

      if (_environment == 'production') {
        _prodToken = currentToken;
        _prodAdminToken = currentAdminToken;
      } else {
        _stagingToken = currentToken;
        _stagingAdminToken = currentAdminToken;
      }

      await ref.read(settingsProvider.notifier).saveSettings(
            prodToken: _prodToken,
            stagingToken: _stagingToken,
            environment: _environment,
            prodAdminToken:
                _prodAdminToken.isNotEmpty ? _prodAdminToken : null,
            stagingAdminToken:
                _stagingAdminToken.isNotEmpty ? _stagingAdminToken : null,
            prodVibrationsEnabled: _prodVibrationsEnabled,
            stagingVibrationsEnabled: _stagingVibrationsEnabled,
            prodShiftReminderMinutes: _prodReminderMinutes,
            stagingShiftReminderMinutes: _stagingReminderMinutes,
          );

      final activeReminder = _environment == 'staging'
          ? _stagingReminderMinutes
          : _prodReminderMinutes;
      if (activeReminder > 0) {
        await ref.read(notificationServiceProvider).requestPermissions();
      }

      if (mounted) {
        // Invalidate and refresh both status and shifts without carrying over old environment cache
        ref.invalidate(currentStatusProvider);
        ref.invalidate(shiftsProvider);
        await Future.wait([
          ref.read(currentStatusProvider.notifier).resetAndRefresh(),
          ref.read(shiftsProvider.notifier).refresh(),
        ]);

        if (mounted) {
          Navigator.of(context).pop();
          final statusState = ref.read(currentStatusProvider);
          final envName = _environment == 'staging' ? 'Staging' : 'Production';
          if (statusState.hasError) {
            final err = statusState.error;
            final msg = (err is ApiException)
                ? '${err.message} (${err.code})'
                : err.toString();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Warning: Failed to connect to $envName: $msg'),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connected to $envName & synced!'),
                backgroundColor: const Color(0xFF0F766E),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune, color: Color(0xFF0F766E)),
          SizedBox(width: 8),
          Text('Server & Credentials'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Configure your Cloudflare Worker URL and device Bearer token to connect your app and home screen widget.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  key: const Key('environment_selector'),
                  segments: const [
                    ButtonSegment(
                      value: 'production',
                      label: Text('Production', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.cloud_done, size: 15),
                    ),
                    ButtonSegment(
                      value: 'staging',
                      label: Text('Staging', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.science, size: 15),
                    ),
                  ],
                  selected: {_environment},
                  onSelectionChanged: (selectedSet) =>
                      _switchEnvironment(selectedSet.first),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final isStaging =
                        (child.key as ValueKey<String>?)?.value == 'staging';
                    final offsetTween = Tween<Offset>(
                      begin: isStaging
                          ? const Offset(0.2, 0.0)
                          : const Offset(-0.2, 0.0),
                      end: Offset.zero,
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: offsetTween.animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_environment),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_environment == 'staging') ...[
                          InkWell(
                            key: const Key('staging_web_link'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              final uri =
                                  Uri.tryParse(AppConfig.stagingApiBaseUrl);
                              if (uri != null) {
                                launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF0F766E)
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.open_in_browser,
                                      size: 18, color: Color(0xFF14B8A6)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Open Staging Web in Browser',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF14B8A6),
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      size: 16, color: Color(0xFF14B8A6)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        // Locked API Base URL Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.lock_outline,
                                          size: 14, color: Color(0xFF94A3B8)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _environment == 'staging'
                                            ? 'Staging API Base URL'
                                            : 'API Base URL',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.content_copy,
                                        size: 16, color: Color(0xFF94A3B8)),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Copy API URL',
                                    onPressed: () {
                                      final url = _environment == 'staging'
                                          ? AppConfig.stagingApiBaseUrl
                                          : AppConfig.defaultApiBaseUrl;
                                      Clipboard.setData(
                                          ClipboardData(text: url));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('API URL copied to clipboard'),
                                          duration: Duration(seconds: 1),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                _environment == 'staging'
                                    ? AppConfig.stagingApiBaseUrl
                                    : AppConfig.defaultApiBaseUrl,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tokenController,
                          obscureText: _obscureToken,
                          decoration: InputDecoration(
                            labelText: _environment == 'staging'
                                ? 'Staging Device Bearer Token'
                                : 'Device Bearer Token',
                            hintText:
                                '64-character hex token from provision script',
                            helperText:
                                'Paste the raw Bearer Token (do NOT paste the token_hash)',
                            helperMaxLines: 2,
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _obscureToken
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureToken = !_obscureToken),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.content_paste),
                                  tooltip: 'Paste from clipboard',
                                  onPressed: () => _pasteTo(_tokenController),
                                ),
                              ],
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Bearer token is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _adminTokenController,
                          obscureText: _obscureAdminToken,
                          decoration: InputDecoration(
                            labelText: _environment == 'staging'
                                ? 'Staging Admin API Token (Optional)'
                                : 'Admin API Token (Optional)',
                            hintText: 'Used for manual shift backfills',
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _obscureAdminToken
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () =>
                                        _obscureAdminToken = !_obscureAdminToken,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.content_paste),
                                  tooltip: 'Paste from clipboard',
                                  onPressed: () =>
                                      _pasteTo(_adminTokenController),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          key: const Key('shift_reminder_dropdown'),
                          initialValue: _currentReminderMinutes,
                          decoration: const InputDecoration(
                            labelText: 'Clock-out Reminder',
                            helperText:
                                'Notify before planned shift length ends',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(
                              Icons.notifications_active_outlined,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Disabled')),
                            DropdownMenuItem(
                                value: 5, child: Text('5 minutes before')),
                            DropdownMenuItem(
                                value: 10, child: Text('10 minutes before')),
                            DropdownMenuItem(
                                value: 15, child: Text('15 minutes before')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _currentReminderMinutes = val);
                            }
                          },
                        ),
                        if (ref.watch(hapticServiceProvider).isSupported) ...[
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Haptic feedback',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Vibrate on clock actions in app and home widget',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            value: _currentVibrationsEnabled,
                            onChanged: (val) => setState(
                                () => _currentVibrationsEnabled = val),
                            activeTrackColor: const Color(0xFF0F766E),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24, color: Color(0xFF334155)),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final versionAsync = ref.watch(versionCheckProvider);
                      final versionInfo = versionAsync.valueOrNull ??
                          VersionInfo(
                            currentVersion: AppConfig.appVersion,
                            isChecking: versionAsync.isLoading,
                            isError: versionAsync.hasError,
                          );

                      final hasUpdate = versionInfo.hasUpdate;

                      return InkWell(
                        key: const Key('android_version_badge'),
                        onTap: () => launchUrl(
                          Uri.parse(
                              'https://github.com/Kamil-Suhak/work-hours-tracker/releases/latest'),
                          mode: LaunchMode.externalApplication,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasUpdate
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF334155),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                hasUpdate
                                    ? Icons.system_update
                                    : Icons.verified_outlined,
                                size: 16,
                                color: hasUpdate
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  versionInfo.displayText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: hasUpdate
                                        ? const Color(0xFFFDE68A)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              if (hasUpdate)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'UPDATE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.code, size: 16),
                      label:
                          const Text('GitHub', style: TextStyle(fontSize: 12)),
                      onPressed: () => launchUrl(
                        Uri.parse(
                            'https://github.com/Kamil-Suhak/work-hours-tracker'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.download_for_offline_outlined,
                          size: 16),
                      label: const Text('Download APK',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () => launchUrl(
                        Uri.parse(
                            'https://github.com/Kamil-Suhak/work-hours-tracker/releases/latest'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save & Sync'),
        ),
      ],
    );
  }
}