import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/profile_service.dart';

/// Edit Profile screen — Shopee-style layout with avatar at top and
/// tappable list rows for Name, Bio, Gender, Birthday, Phone, Email.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  String? _avatarUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _avatarUrl = auth.avatarUrl;
  }

  /// Mask a phone number: show last 2 digits.
  String _maskPhone(String phone) {
    if (phone.isEmpty) return '';
    if (phone.length <= 2) return phone;
    return '*' * (phone.length - 2) + phone.substring(phone.length - 2);
  }

  /// Mask birthday: show **/**/YYYY format (only year visible).
  String _maskBirthday(String? birthday) {
    if (birthday == null || birthday.isEmpty) return '';
    // Try parsing ISO date (YYYY-MM-DD) first
    final date = DateTime.tryParse(birthday);
    if (date != null) return '**/**/${date.year}';
    // Try extracting 4-digit year from any format
    final yearMatch = RegExp(r'(\d{4})').firstMatch(birthday);
    if (yearMatch != null) return '**/**/${yearMatch.group(1)}';
    return birthday;
  }

  /// Format gender for display.
  String _formatGender(String? gender) {
    if (gender == null || gender.isEmpty) return '';
    // Capitalize first letter
    return gender[0].toUpperCase() + gender.substring(1).toLowerCase();
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Shared profile save — preserves existing fields unless explicitly overridden.
  Future<bool> _saveProfile(
    AuthProvider auth, {
    String? name,
    String? phone,
    String? bio,
    String? gender,
    String? birthday,
  }) {
    return auth.updateProfile(
      fullName: name ?? auth.displayName,
      phone: phone ?? (auth.displayPhone.isNotEmpty ? auth.displayPhone : null),
      newAvatarUrl: _avatarUrl,
      bio: bio ?? auth.profile?['bio']?.toString(),
      gender: gender ?? auth.profile?['gender']?.toString(),
      birthday: birthday ?? auth.profile?['birthday']?.toString(),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppConstants.bodyStyle(
        fontSize: 14,
        color: AppConstants.secondary.withValues(alpha: 0.5),
      ),
      filled: true,
      fillColor: const Color(0xFFF5F5F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppConstants.primary),
      ),
    );
  }

  // ── Edit handlers ──────────────────────────────────────────────

  Future<void> _pickAndUploadAvatar() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.currentUser?['id']?.toString();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in again before updating your photo.'),
          backgroundColor: AppConstants.error,
        ),
      );
      return;
    }

    try {
      final picked = await ProfileService.instance.pickAvatarImage();
      if (picked == null) return;

      setState(() => _isUploading = true);
      final avatarUrl = await ProfileService.instance.uploadAvatar(
        userId: userId,
        filePath: picked.path,
      );
      final success = await auth.updateProfile(
        fullName: auth.displayName,
        phone: auth.displayPhone.isNotEmpty ? auth.displayPhone : null,
        newAvatarUrl: avatarUrl,
        bio: auth.profile?['bio']?.toString(),
        gender: auth.profile?['gender']?.toString(),
        birthday: auth.profile?['birthday']?.toString(),
      );

      if (!mounted) return;
      setState(() {
        _avatarUrl = avatarUrl;
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Profile photo updated'
                : auth.errorMessage ?? 'Unable to update profile photo.',
          ),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    } catch (e) {
      debugPrint('[EditProfileScreen] Avatar upload failed: $e');
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo upload failed — please try again.'),
          backgroundColor: AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editName() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final controller = TextEditingController(text: auth.displayName);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit Name',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            style: AppConstants.bodyStyle(fontSize: 14),
            decoration: _inputDecoration('Enter your name'),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text('Save', style: AppConstants.bodyStyle(color: AppConstants.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final success = await _saveProfile(auth, name: controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Name updated' : auth.errorMessage ?? 'Failed to update'),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editBio() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentBio = auth.profile?['bio']?.toString() ?? '';
    final controller = TextEditingController(text: currentBio);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit Bio',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tell others a little about yourself.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                maxLines: 4,
                maxLength: 200,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: _inputDecoration('Write something about yourself...'),
                validator: (val) {
                  if (val != null && val.length > 200) {
                    return 'Bio must be 200 characters or less';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text('Save', style: AppConstants.bodyStyle(color: AppConstants.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final newBio = controller.text.trim();
      final success = await _saveProfile(auth, bio: newBio.isNotEmpty ? newBio : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Bio updated' : auth.errorMessage ?? 'Failed to update'),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editPhone() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final controller = TextEditingController(text: auth.displayPhone);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit Phone',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            style: AppConstants.bodyStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. 09XX-XXX-XXXX',
              hintStyle: AppConstants.bodyStyle(
                fontSize: 14,
                color: AppConstants.secondary.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppConstants.primary),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save', style: AppConstants.bodyStyle(color: AppConstants.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final phone = controller.text.trim();
      final success = await _saveProfile(auth, phone: phone.isNotEmpty ? phone : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Phone updated' : auth.errorMessage ?? 'Failed to update'),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editGender() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentGender = auth.profile?['gender']?.toString() ?? '';

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          'Select Gender',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        children: AppConstants.customerGenderOptions.map((option) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, option),
            child: Row(
              children: [
                Icon(
                  currentGender == option ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: AppConstants.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(option, style: AppConstants.bodyStyle(fontSize: 15)),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected != null && mounted) {
      final success = await _saveProfile(auth, gender: selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Gender updated' : auth.errorMessage ?? 'Failed to update'),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editBirthday() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentBirthday = auth.profile?['birthday']?.toString();

    DateTime? initialDate;
    if (currentBirthday != null && currentBirthday.isNotEmpty) {
      initialDate = DateTime.tryParse(currentBirthday);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppConstants.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppConstants.secondary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      // Store as ISO date string (YYYY-MM-DD)
      final isoDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      final success = await _saveProfile(auth, birthday: isoDate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Birthday updated' : auth.errorMessage ?? 'Failed to update'),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  Future<void> _editEmail() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final controller = TextEditingController(text: auth.displayEmail);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Change Email',
          style: AppConstants.bodyStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A verification link will be sent to your new email address.',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                style: AppConstants.bodyStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppConstants.borderGray.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppConstants.primary),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter an email';
                  final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                  if (!emailRegex.hasMatch(val.trim())) return 'Please enter a valid email';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppConstants.bodyStyle(color: AppConstants.secondary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text('Send Verification', style: AppConstants.bodyStyle(color: AppConstants.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final success = await auth.updateEmail(controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Verification email sent to ${controller.text.trim()}'
                : auth.errorMessage ?? 'Failed to update email',
          ),
          backgroundColor: success ? AppConstants.success : AppConstants.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Edit Profile',
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ── Avatar Section ────────────────────────────────
            _buildAvatarSection(auth),
            const SizedBox(height: 12),

            // ── Name & Bio ───────────────────────────────────
            _buildSection([
              _profileRow(
                title: 'Name',
                value: auth.displayName.isNotEmpty ? auth.displayName : 'Not set',
                onTap: _editName,
              ),
              _divider(),
              _profileRow(
                title: 'Bio',
                value: (auth.profile?['bio']?.toString().isNotEmpty ?? false)
                    ? auth.profile!['bio'].toString()
                    : null,
                actionLabel: (auth.profile?['bio']?.toString().isNotEmpty ?? false)
                    ? null
                    : 'Set Now',
                onTap: _editBio,
              ),
            ]),
            const SizedBox(height: 12),

            // ── Gender & Birthday ─────────────────────────────
            _buildSection([
              _profileRow(
                title: 'Gender',
                titleInfoIcon: true,
                value: _formatGender(auth.profile?['gender']?.toString()),
                actionLabel: _formatGender(auth.profile?['gender']?.toString()).isEmpty ? 'Set Now' : null,
                onTap: _editGender,
              ),
              _divider(),
              _profileRow(
                title: 'Birthday',
                titleInfoIcon: true,
                value: _maskBirthday(auth.profile?['birthday']?.toString()),
                actionLabel: _maskBirthday(auth.profile?['birthday']?.toString()).isEmpty ? 'Set Now' : null,
                onTap: _editBirthday,
              ),
            ]),
            const SizedBox(height: 12),

            // ── Phone & Email ─────────────────────────────────
            _buildSection([
              _profileRow(
                title: 'Phone',
                value: auth.displayPhone.isNotEmpty
                    ? _maskPhone(auth.displayPhone)
                    : null,
                actionLabel: auth.displayPhone.isNotEmpty ? null : 'Set Now',
                onTap: _editPhone,
              ),
              _divider(),
              _profileRow(
                title: 'Email',
                value: auth.displayEmail.isNotEmpty
                    ? auth.displayEmail
                    : null,
                actionLabel: auth.displayEmail.isNotEmpty ? null : 'Set Now',
                onTap: _editEmail,
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Avatar section ─────────────────────────────────────────────
  Widget _buildAvatarSection(AuthProvider auth) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: AppConstants.primary.withValues(alpha: 0.1),
                backgroundImage:
                    _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                child: _isUploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppConstants.primary,
                        ),
                      )
                    : _avatarUrl == null
                        ? Text(
                            _initials(auth.displayName),
                            style: AppConstants.headlineStyle(
                              fontSize: 28,
                              color: AppConstants.primary,
                            ),
                          )
                        : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,                  child: GestureDetector(
                  onTap: _isUploading ? null : _pickAndUploadAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppConstants.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.0,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Edit label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_outlined,
                size: 14,
                color: AppConstants.secondary.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                'Edit',
                style: AppConstants.bodyStyle(
                  fontSize: 13,
                  color: AppConstants.secondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.borderGray.withValues(alpha: 0.3),
        ),
      ),
      child: Column(children: children),
    );
  }

  // ── Profile row ────────────────────────────────────────────────
  Widget _profileRow({
    required String title,
    required VoidCallback onTap,
    String? value,
    String? actionLabel,
    bool titleInfoIcon = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(fontSize: 15),
              ),
              if (titleInfoIcon) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.help_outline,
                  size: 16,
                  color: AppConstants.secondary.withValues(alpha: 0.4),
                ),
              ],
              const Spacer(),
              if (actionLabel != null)
                Text(
                  actionLabel,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.accent,
                  ),
                )
              else if (value != null && value.isNotEmpty)
                Text(
                  value,
                  style: AppConstants.bodyStyle(
                    fontSize: 14,
                    color: AppConstants.secondary.withValues(alpha: 0.6),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppConstants.secondary.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Divider ────────────────────────────────────────────────────
  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: AppConstants.borderGray.withValues(alpha: 0.3),
      indent: 16,
      endIndent: 16,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────
  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
