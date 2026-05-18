import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../utils/app_error_message.dart';
import '../utils/session_manager.dart';
import '../utils/storage.dart';
import '../widgets/app_logo.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileViewData> _profileFuture;
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _updatingPassword = false;
  bool _updatingPhoto = false;

  Future<String?> _pickAndCropPhoto(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;

    try {
      picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
      );
    } on PlatformException catch (error) {
      throw Exception(
        error.message ?? 'Photo picker could not open. Please try again.',
      );
    } catch (_) {
      throw Exception('Photo processing failed. Please try another image.');
    }

    if (picked == null) {
      return null;
    }

    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Photo',
            toolbarColor: const Color(0xFF1E3A8A),
            toolbarWidgetColor: Colors.white,
            statusBarColor: const Color(0xFF1E3A8A),
            backgroundColor: Colors.black,
            activeControlsWidgetColor: const Color(0xFF1D4ED8),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
        ],
      );

      if (cropped == null) {
        return null;
      }

      return cropped.path;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Profile photo cropper failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw Exception('Photo editing was cancelled or failed. Please try again.');
    } catch (error, stackTrace) {
      debugPrint('Profile photo cropper failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw Exception('Photo editing was cancelled or failed. Please try again.');
    }
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final croppedPath = await _pickAndCropPhoto(source);
      if (croppedPath == null) {
        return;
      }

      final token = await Storage.getToken();
      if (token == null) {
        if (!mounted) return;
        _showSnackBar('Login session is missing. Please log in again.');
        return;
      }

      if (mounted) {
        setState(() => _updatingPhoto = true);
      }
      await ApiService.updateProfilePhoto(token, croppedPath);
      if (!mounted) return;
      _showSnackBar('Profile photo updated successfully.');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(userFriendlyErrorMessage(e, action: 'photo_upload'));
    } finally {
      if (mounted) setState(() => _updatingPhoto = false);
    }
  }

  String? _normalizedPhotoUrl(String? photoUrl) {
    final trimmed = photoUrl?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showProfilePhotoViewer(String photoUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    photoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Profile photo could not be loaded.',
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoOptions({String? photoUrl}) {
    final normalizedPhotoUrl = _normalizedPhotoUrl(photoUrl);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Update Profile Photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (normalizedPhotoUrl != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.visibility_rounded,
                      color: Color(0xFF1D4ED8)),
                ),
                title: const Text('View profile photo'),
                onTap: () {
                  Navigator.pop(context);
                  _showProfilePhotoViewer(normalizedPhotoUrl);
                },
              ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.camera_alt_rounded, color: Color(0xFF1D4ED8)),
              ),
              title: const Text('Take photo with camera'),
              onTap: () async {
                Navigator.pop(context);
                await Future<void>.delayed(const Duration(milliseconds: 120));
                if (!mounted) return;
                await _pickAndUploadPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child:
                    Icon(Icons.photo_library_rounded, color: Color(0xFF1D4ED8)),
              ),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.pop(context);
                await Future<void>.delayed(const Duration(milliseconds: 120));
                if (!mounted) return;
                await _pickAndUploadPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<_ProfileViewData> _loadProfile() async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Login session is missing. Please log in again.');
    }

    final payload = await ApiService.getHomeProfile(token);
    final user = payload['user'];
    final userMap =
        user is Map ? user.cast<String, dynamic>() : const <String, dynamic>{};

    final cachedProfile = UserProfile.fromDynamic(userMap);
    if (cachedProfile != null) {
      await Storage.saveUserProfile(cachedProfile);
    }

    return _ProfileViewData(user: userMap);
  }

  void _refresh() {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      _showSnackBar('Login session is missing. Please log in again.');
      return;
    }

    setState(() {
      _updatingPassword = true;
    });

    try {
      await ApiService.updateHomePassword(
        token,
        currentPassword: _currentPasswordController.text.trim(),
        password: _newPasswordController.text.trim(),
        passwordConfirmation: _confirmPasswordController.text.trim(),
      );

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) {
        return;
      }
      _showSnackBar('Password updated successfully.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(userFriendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _updatingPassword = false;
        });
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: const Text(
          'Do you want to log out?\nYour session will end and you will need to log in again.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SessionManager.forceLogoutToLogin();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      backgroundColor:
          isDark ? const Color(0xFF0B1F3A) : const Color(0xFFF4F6FA),
      body: FutureBuilder<_ProfileViewData>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data ?? const _ProfileViewData(user: {});
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final profileCard = _buildProfileCard(isDark, data.user);
                final passwordCard = _buildPasswordCard(isDark);

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: profileCard),
                          const SizedBox(width: 16),
                          Expanded(child: passwordCard),
                        ],
                      )
                    else ...[
                      profileCard,
                      const SizedBox(height: 16),
                      passwordCard,
                    ],
                    const SizedBox(height: 16),
                    _buildLogoutCard(isDark),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileCard(bool isDark, Map<String, dynamic> user) {
    final profile = UserProfile.fromDynamic(user);
    final role = _readNested(user, 'role', 'name');
    final post = _readNested(user, 'post', 'name');
    final reportingOfficer = _readNested(user, 'reporting_officer', 'name');
    final reportingDesignation =
        _readNested(user, 'reporting_officer', 'designation');
    final reportingLine = [
      if (reportingOfficer.isNotEmpty) reportingOfficer,
      if (reportingDesignation.isNotEmpty) reportingDesignation,
    ].join(' | ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _updatingPhoto
                      ? null
                      : () => _showPhotoOptions(photoUrl: profile?.photoUrl),
                  child: Stack(
                    children: [
                      _ProfilePhoto(photoUrl: profile?.photoUrl),
                      if (_updatingPhoto)
                        const Positioned.fill(
                          child: CircleAvatar(
                            backgroundColor: Colors.black45,
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 14, color: Color(0xFF1D4ED8)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stringOr(user['name'], fallback: 'RPF User'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stringOr(user['designation'], fallback: 'Duty Staff'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _detailGrid(
            isDark: isDark,
            items: [
              _ProfileField('Full Name', _stringOr(user['name'])),
              _ProfileField('Mobile', _stringOr(user['mobile'])),
              _ProfileField('Email', _stringOr(user['email'])),
              _ProfileField('Role', role),
              _ProfileField('Post', post),
              _ProfileField('Reporting Officer', reportingLine),
              _ProfileField('Status', _stringOr(user['status_label'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.logout_rounded,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logout',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF101828),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _confirmLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reset Password',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Only your password can be changed. The rest of the profile details are read-only.',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : const Color(0xFF1D4ED8))
                        .withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: isDark ? Colors.white : const Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _passwordField(
              controller: _currentPasswordController,
              label: 'Current Password',
              hint: 'Enter current password',
              obscure: _hideCurrentPassword,
              toggle: () {
                setState(() {
                  _hideCurrentPassword = !_hideCurrentPassword;
                });
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Current password is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 640;
                final newPasswordField = _passwordField(
                  controller: _newPasswordController,
                  label: 'New Password',
                  hint: 'New password',
                  obscure: _hideNewPassword,
                  toggle: () {
                    setState(() {
                      _hideNewPassword = !_hideNewPassword;
                    });
                  },
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'New password is required.';
                    }
                    if (trimmed.length < 6) {
                      return 'Minimum 6 characters required.';
                    }
                    if (trimmed == _currentPasswordController.text.trim()) {
                      return 'New password must be different from the current password.';
                    }
                    return null;
                  },
                );
                final confirmPasswordField = _passwordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  hint: 'Confirm password',
                  obscure: _hideConfirmPassword,
                  toggle: () {
                    setState(() {
                      _hideConfirmPassword = !_hideConfirmPassword;
                    });
                  },
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Please confirm your password.';
                    }
                    if (trimmed != _newPasswordController.text.trim()) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                );

                if (narrow) {
                  return Column(
                    children: [
                      newPasswordField,
                      const SizedBox(height: 12),
                      confirmPasswordField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: newPasswordField),
                    const SizedBox(width: 12),
                    Expanded(child: confirmPasswordField),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111827) : const Color(0xFFF3F7FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 430;
                  final infoText = Text(
                    'Use at least 6 characters and keep it different from your current password.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  );

                  final actionButton = FilledButton(
                    onPressed: _updatingPassword ? null : _updatePassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _updatingPassword
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Update Password'),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color:
                                  isDark ? Colors.white70 : const Color(0xFF1D4ED8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: infoText),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: actionButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color:
                                  isDark ? Colors.white70 : const Color(0xFF1D4ED8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: infoText),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      actionButton,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailGrid({
    required bool isDark,
    required List<_ProfileField> items,
  }) {
    final visibleItems =
        items.where((item) => item.value.trim().isNotEmpty).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * 12)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: visibleItems
              .map(
                (item) => SizedBox(
                  width: tileWidth,
                  child: _detailTile(
                    isDark: isDark,
                    label: item.label,
                    value: item.value,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _detailTile({
    required bool isDark,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        suffixIcon: IconButton(
          onPressed: toggle,
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }

  String _readNested(Map<String, dynamic> root, String key, String nestedKey) {
    final value = root[key];
    if (value is Map) {
      return _stringOr(value[nestedKey]);
    }
    return '';
  }

  String _stringOr(dynamic value, {String fallback = '-'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _ProfilePhoto extends StatelessWidget {
  final String? photoUrl;

  const _ProfilePhoto({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final trimmed = photoUrl?.trim() ?? '';
    if (trimmed.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: AppLogo(
            size: 42,
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          trimmed,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              color: Colors.white.withOpacity(0.16),
              child: const Center(
                child: AppLogo(
                  size: 42,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileField {
  final String label;
  final String value;

  const _ProfileField(this.label, this.value);
}

class _ProfileViewData {
  final Map<String, dynamic> user;

  const _ProfileViewData({required this.user});
}
