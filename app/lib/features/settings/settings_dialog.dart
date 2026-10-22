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
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _adminTokenController;
  bool _obscureToken = true;
  bool _obscureAdminToken = true;
  bool _isSaving = false;
  bool _vibrationsEnabled = true;
  int _shiftReminderMinutes = 0;
  String _environment = 'production';
  String _prodUrl = '';
  String _prodToken = '';
  String _stagingUrl = '';
  String _stagingToken = '';

  @override
  void initState() {
    super.initState();
    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.value;

    _environment =
        (settings?.environment == 'staging') ? 'staging' : 'production';
    _shiftReminderMinutes = settings?.shiftReminderMinutes ?? 0;
    _vibrationsEnabled = settings?.vibrationsEnabled ?? true;

    _prodUrl = (settings?.prodUrl != null &&
            settings!.prodUrl.isNotEmpty &&
            settings.prodUrl != 'https://work-hours-api.workers.dev')
        ? settings.prodUrl
        : AppConfig.defaultApiBaseUrl;
    _prodToken = settings?.prodToken ?? '';

    _stagingUrl = (settings?.stagingUrl != null &&
            settings!.stagingUrl.isNotEmpty)
        ? settings.stagingUrl
        : AppConfig.stagingApiBaseUrl;
    _stagingToken = settings?.stagingToken ?? '';

    final initialUrl = _environment == 'staging' ? _stagingUrl : _prodUrl;
    final initialToken =
        _environment == 'staging' ? _stagingToken : _prodToken;

    _urlController = TextEditingController(text: initialUrl);
    _tokenController = TextEditingController(text: initialToken);
    _adminTokenController = TextEditingController(
      text: settings?.adminToken ?? '',
    );
  }

  void _switchEnvironment(String targetEnv) {
    if (_environment == targetEnv) return;

    if (_environment == 'production') {
      _prodUrl = _urlController.text.trim();
      _prodToken = _tokenController.text.trim();
    } else {
      _stagingUrl = _urlController.text.trim();
      _stagingToken = _tokenController.text.trim();
    }

    setState(() {
      _environment = targetEnv;
      if (targetEnv == 'production') {
        _urlController.text =
            _prodUrl.isNotEmpty ? _prodUrl : AppConfig.defaultApiBaseUrl;
        _tokenController.text = _prodToken;
      } else {
        _urlController.text =
            _stagingUrl.isNotEmpty ? _stagingUrl : AppConfig.stagingApiBaseUrl;
        _tokenController.text = _stagingToken;
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
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
      final currentUrl = _urlController.text.trim();
      final currentToken = _tokenController.text.trim();
      final adminToken = _adminTokenController.text.trim();

      if (_environment == 'production') {
        _prodUrl = currentUrl;
        _prodToken = currentToken;
      } else {
        _stagingUrl = currentUrl;
        _stagingToken = currentToken;
      }

      await ref.read(settingsProvider.notifier).saveSettings(
            prodUrl: _prodUrl,
            prodToken: _prodToken,
            stagingUrl: _stagingUrl,
            stagingToken: _stagingToken,
            environment: _environment,
            adminToken: adminToken.isNotEmpty ? adminToken : null,
            vibrationsEnabled: _vibrationsEnabled,
            shiftReminderMinutes: _shiftReminderMinutes,
          );

      if (_shiftReminderMinutes > 0) {
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
                              final targetUrl = _urlController.text.trim().isNotEmpty
                                  ? _urlController.text.trim()
                                  : AppConfig.stagingApiBaseUrl;
                              final uri = Uri.tryParse(targetUrl);
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
                        TextFormField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: _environment == 'staging'
                                ? 'Staging Worker Base URL'
                                : 'Worker Base URL',
                            hintText:
                                'https://work-hours-api.<subdomain>.workers.dev',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.content_paste),
                              tooltip: 'Paste from clipboard',
                              onPressed: () => _pasteTo(_urlController),
                            ),
                          ),
                          keyboardType: TextInputType.url,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Base URL is required';
                            }
                            final uri = Uri.tryParse(val.trim());
                            if (uri == null ||
                                !uri.hasScheme ||
                                !uri.hasAuthority) {
                              return 'Enter a valid URL (e.g. https://...)';
                            }
                            return null;
                          },
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _adminTokenController,
                  obscureText: _obscureAdminToken,
                  decoration: InputDecoration(
                    labelText: 'Admin API Token (Optional)',
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
                            () => _obscureAdminToken = !_obscureAdminToken,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste),
                          tooltip: 'Paste from clipboard',
                          onPressed: () => _pasteTo(_adminTokenController),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const Key('shift_reminder_dropdown'),
                  initialValue: _shiftReminderMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Clock-out Reminder',
                    helperText: 'Notify before planned shift length ends',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.notifications_active_outlined,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Disabled')),
                    DropdownMenuItem(value: 5, child: Text('5 minutes before')),
                    DropdownMenuItem(
                        value: 10, child: Text('10 minutes before')),
                    DropdownMenuItem(
                        value: 15, child: Text('15 minutes before')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _shiftReminderMinutes = val);
                    }
                  },
                ),
                if (ref.watch(hapticServiceProvider).isSupported) ...[
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Haptic feedback',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Vibrate on clock actions in app and home widget',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    value: _vibrationsEnabled,
                    onChanged: (val) =>
                        setState(() => _vibrationsEnabled = val),
                    activeTrackColor: const Color(0xFF0F766E),
                  ),
                ],
                const Divider(height: 24, color: Color(0xFF334155)),
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
