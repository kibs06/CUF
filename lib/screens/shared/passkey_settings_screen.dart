// Supabase's Passkey type is @experimental while passkeys are in beta.
// ignore_for_file: experimental_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Passkey;

import '../../constants/app_constants.dart';
import '../../services/passkey_service.dart';

/// Account & Security → Passkeys.
///
/// A passkey is a real WebAuthn credential: the private key is held by the
/// device's credential provider and unlocked with the screen lock, fingerprint
/// or face. The server only ever receives the public key.
class PasskeySettingsScreen extends StatefulWidget {
  const PasskeySettingsScreen({super.key, this.gateway});

  /// Injectable for widget tests; defaults to the shared Supabase service.
  final PasskeyGateway? gateway;

  @override
  State<PasskeySettingsScreen> createState() => _PasskeySettingsScreenState();
}

class _PasskeySettingsScreenState extends State<PasskeySettingsScreen> {
  late final PasskeyGateway _gateway =
      widget.gateway ?? PasskeyService.instance;

  bool _loading = true;
  bool _supported = true;
  bool _adding = false;
  String? _deletingId;
  String? _loadError;
  List<Passkey> _passkeys = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final supported = await _gateway.isSupported();
    List<Passkey> passkeys = const [];
    String? error;
    try {
      passkeys = await _gateway.list();
    } catch (e) {
      debugPrint('[passkeys] list failed: $e');
      error = passkeyErrorMessage(e);
    }

    if (!mounted) return;
    setState(() {
      _supported = supported;
      _passkeys = passkeys;
      _loadError = error;
      _loading = false;
    });
  }

  Future<void> _add() async {
    if (_adding || !_supported) return;
    setState(() => _adding = true);
    try {
      final passkey = await _gateway.register();
      if (!mounted) return;
      setState(() {
        _passkeys = [..._passkeys, passkey];
        _loadError = null;
      });
      _showMessage('Passkey added. You can now sign in with it.');
    } catch (e) {
      if (isPasskeyCancellation(e)) return;
      debugPrint('[passkeys] register failed: $e');
      _showMessage(passkeyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(Passkey passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceLight,
        title: Text(
          'Remove this passkey?',
          style: AppConstants.headlineStyle(fontSize: 17),
        ),
        content: Text(
          '${passkey.friendlyName?.isNotEmpty == true ? passkey.friendlyName : 'This passkey'} '
          'will no longer sign you in on this device. Your password still works.',
          style: AppConstants.bodyStyle(
            fontSize: 14,
            color: AppConstants.secondary.withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: AppConstants.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingId = passkey.id);
    try {
      await _gateway.delete(passkey.id);
      if (!mounted) return;
      setState(() {
        _passkeys = _passkeys.where((p) => p.id != passkey.id).toList();
      });
      _showMessage('Passkey removed.');
    } catch (e) {
      debugPrint('[passkeys] delete failed: $e');
      _showMessage(passkeyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppConstants.error : AppConstants.success,
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceLight,
      appBar: AppBar(
        title: Text(
          'Passkeys',
          style: AppConstants.bodyStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppConstants.secondary,
          ),
        ),
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          color: AppConstants.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppConstants.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _introCard(),
            if (!_supported) ...[
              const SizedBox(height: 12),
              _noticeCard(
                icon: Icons.info_outline,
                color: AppConstants.error,
                title: 'Passkeys are not available on this device',
                body:
                    'Use a device with Android 9 or later, Google Play Services and a screen lock set up.',
              ),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 12),
              _noticeCard(
                icon: Icons.error_outline,
                color: AppConstants.error,
                title: 'Could not load your passkeys',
                body: _loadError!,
                action: TextButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your passkeys',
                    style: AppConstants.headlineStyle(fontSize: 16),
                  ),
                ),
                if (!_loading)
                  Text(
                    '${_passkeys.length}',
                    style: AppConstants.bodyStyle(
                      fontSize: 13,
                      color: AppConstants.secondary.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppConstants.primary),
                ),
              )
            else if (_passkeys.isEmpty)
              _emptyCard()
            else
              ..._passkeys.map(_passkeyCard),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _supported && !_adding ? _add : null,
                icon: _adding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppConstants.inkInverse,
                        ),
                      )
                    : const Icon(Icons.add, size: 21),
                label: Text(
                  _adding ? 'Waiting for device…' : 'Add a passkey',
                  style: AppConstants.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.inkInverse,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppConstants.primary,
                  disabledBackgroundColor: AppConstants.primary.withValues(
                    alpha: 0.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppConstants.buttonRadius,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your passkey stays on this device. CUFMAI only stores the '
              'public key, never your fingerprint or face data.',
              textAlign: TextAlign.center,
              style: AppConstants.bodyStyle(
                fontSize: 12,
                height: 1.45,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppConstants.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppConstants.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.key_rounded,
              color: AppConstants.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sign in without a password',
                  style: AppConstants.headlineStyle(fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  'Use your fingerprint, face or screen lock to sign in. '
                  'Passkeys are phishing-resistant and never leave your device.',
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            Icons.key_off_outlined,
            size: 32,
            color: AppConstants.secondary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 8),
          Text(
            'No passkey yet',
            style: AppConstants.bodyStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Add one above to sign in faster next time.',
            textAlign: TextAlign.center,
            style: AppConstants.bodyStyle(
              fontSize: 12,
              color: AppConstants.secondary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passkeyCard(Passkey passkey) {
    final deleting = _deletingId == passkey.id;
    final name = passkey.friendlyName?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppConstants.sellerCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppConstants.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.key_rounded,
              color: AppConstants.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? 'Passkey' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Added ${_formatDate(passkey.createdAt)}'
                  '${passkey.lastUsedAt == null ? ' · Never used' : ' · Last used ${_formatDate(passkey.lastUsedAt!)}'}',
                  style: AppConstants.bodyStyle(
                    fontSize: 11.5,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          if (deleting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppConstants.error,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Remove passkey',
              onPressed: () => _delete(passkey),
              icon: Icon(
                Icons.delete_outline,
                size: 21,
                color: AppConstants.error.withValues(alpha: 0.75),
              ),
            ),
        ],
      ),
    );
  }

  Widget _noticeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppConstants.bodyStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppConstants.bodyStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppConstants.secondary.withValues(alpha: 0.7),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
