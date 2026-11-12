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
  bool _obscureToken = true;
  bool _isSaving = false;
  String _environment = 'production';

  String _prodToken = '';
  int _prodReminderMinutes = 0;
  bool _prodVibrationsEnabled = true;

  String _stagingToken = '';
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
    _prodReminderMinutes =
        settings?.prodReminderMinutes ?? settings?.shiftReminderMinutes ?? 0;
    _prodVibrationsEnabled =
        settings?.prodVibrationsEnabled ?? settings?.vibrationsEnabled ?? true;

    _stagingToken = settings?.stagingToken ?? '';
    _stagingReminderMinutes = settings?.stagingReminderMinutes ?? 0;
    _stagingVibrationsEnabled = settings?.stagingVibrationsEnabled ?? true;

    final initialToken =
        _environment == 'staging' ? _stagingToken : _prodToken;

    _tokenController = TextEditingController(text: initialToken);
  }

  void _switchEnvironment(String targetEnv) {
    if (_environment == targetEnv) return;

    if (_environment == 'production') {
      _prodToken = _tokenController.text.trim();
    } else {
      _stagingToken = _tokenController.text.trim();
    }

    setState(() {
      _environment = targetEnv;
      _tokenController.text =
          targetEnv == 'production' ? _prodToken : _stagingToken;
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
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

      if (_environment == 'production') {
        _prodToken = currentToken;
      } else {
        _stagingToken = currentToken;
      }

      await ref.read(settingsProvider.notifier).saveSettings(
            prodToken: _prodToken,
            stagingToken: _stagingToken,
            environment: _environment,
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
      backgroundColor: const Color(0xFF1E293B),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      title: const Row(
        children: [
          Icon(Icons.tune, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Flexible(child: Text('Server & Credentials')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  onSelectionChanged: _isSaving
                      ? null
                      : (selectedSet) => _switchEnvironment(selectedSet.first),
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
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('staging_web_link'),
                              icon: const Icon(Icons.open_in_browser, size: 16),
                              label: const Text(
                                'Open Staging Web in Browser',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF34D399),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: () {
                                final uri =
                                    Uri.tryParse(AppConfig.stagingApiBaseUrl);
                                if (uri != null) {
                                  launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Locked API Base URL Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lock_outline,
                                      size: 14, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _environment == 'staging'
                                          ? 'Staging API Base URL'
                                          : 'API Base URL',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.content_copy,
                                        size: 16, color: Color(0xFF94A3B8)),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
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
                          enabled: !_isSaving,
                          obscureText: _obscureToken,
                          decoration: InputDecoration(
                            labelText: _environment == 'staging'
                                ? 'Bearer Token (Staging)'
                                : 'Device Bearer Token',
                            hintText: '64-char hex token',
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
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(
                                          () => _obscureToken = !_obscureToken),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.content_paste),
                                  tooltip: 'Paste from clipboard',
                                  onPressed: _isSaving
                                      ? null
                                      : () => _pasteTo(_tokenController),
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
                        DropdownButtonFormField<int>(
                          key: const Key('shift_reminder_dropdown'),
                          initialValue: _currentReminderMinutes,
                          decoration: const InputDecoration(
                            labelText: 'Target End Reminder',
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
                          onChanged: _isSaving
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(
                                        () => _currentReminderMinutes = val);
                                  }
                                },
                        ),
                        if (ref.watch(hapticServiceProvider).isSupported) ...[
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Haptic feedback',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            value: _currentVibrationsEnabled,
                            onChanged: _isSaving
                                ? null
                                : (val) => setState(
                                    () => _currentVibrationsEnabled = val),
                            activeTrackColor: const Color(0xFF10B981),
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
                      final versionInfo = versionAsync.value ??
                          VersionInfo(
                            currentVersion: AppConfig.appVersion,
                            isChecking: versionAsync.isLoading,
                            isError: versionAsync.hasError,
                          );

                      final latestColor = versionInfo.hasUpdate
                          ? const Color(0xFFFBBF24)
                          : (versionInfo.isUpToDate
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8));

                      return InkWell(
                        key: const Key('android_version_badge'),
                        onTap: () => launchUrl(
                          Uri.parse(
                              'https://github.com/Kamil-Suhak/work-hours-tracker/releases/latest'),
                          mode: LaunchMode.externalApplication,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Latest version: '),
                                TextSpan(
                                  text: versionInfo.latestDisplay,
                                  style: TextStyle(
                                    color: latestColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' | Current version: ${versionInfo.currentDisplay}',
                                ),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
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
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
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
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
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