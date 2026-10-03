import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../clock/clock_notifier.dart';
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

  @override
  void initState() {
    super.initState();
    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.value;

    _urlController = TextEditingController(
      text: settings?.baseUrl ?? defaultApiBaseUrl,
    );
    _tokenController = TextEditingController(
      text: settings?.deviceToken ?? '',
    );
    _adminTokenController = TextEditingController(
      text: settings?.adminToken ?? '',
    );
    _vibrationsEnabled = settings?.vibrationsEnabled ?? true;
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
      final url = _urlController.text.trim();
      final token = _tokenController.text.trim();
      final adminToken = _adminTokenController.text.trim();

      await ref.read(settingsProvider.notifier).saveSettings(
            baseUrl: url,
            deviceToken: token,
            adminToken: adminToken.isNotEmpty ? adminToken : null,
            vibrationsEnabled: _vibrationsEnabled,
          );

      if (mounted) {
        // Trigger a fresh status fetch with the new credentials
        ref.read(currentStatusProvider.notifier).refreshStatus();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved & synced to Android widget!'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
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
                const SizedBox(height: 20),
                TextFormField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Worker Base URL',
                    hintText: 'https://work-hours-api.<subdomain>.workers.dev',
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
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
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
                    labelText: 'Device Bearer Token',
                    hintText: 'Paste hex token from provision script',
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
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
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
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Haptic feedback',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Vibrate on clock actions in app and home widget',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _vibrationsEnabled,
                  onChanged: (val) => setState(() => _vibrationsEnabled = val),
                  activeColor: const Color(0xFF0F766E),
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
