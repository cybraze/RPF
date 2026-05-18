import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/tracking_service.dart';
import '../utils/app_error_message.dart';
import '../utils/background_tracking_prep.dart';
import '../utils/storage.dart';
import '../widgets/app_logo.dart';
import 'dashboard_screen.dart';
import 'splash_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _passwordVisible = false;
  bool _isLoading = false;
  bool _isForgotMode = false;

  final _cugController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _redirectIfLoggedIn();
  }

  Future<void> _redirectIfLoggedIn() async {
    final token = await Storage.getToken();
    if (token != null && token.isNotEmpty && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  @override
  void dispose() {
    _cugController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_cugController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showMsg('CUG number and password are required.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.login(
        _cugController.text.trim(),
        _passwordController.text.trim(),
      );
      final token = response['data']['token'];
      await Storage.saveToken(token);
      final userId = (response['data']?['user']?['id'] ??
          response['data']?['employee']?['id'] ??
          response['data']?['id']) as num?;
      if (userId != null) await Storage.saveUserId(userId.toInt());
      final profile = ApiService.extractUserProfileFromLoginResponse(response);
      if (profile != null) {
        await Storage.saveUserProfile(UserProfile(
          id: userId?.toInt() ?? profile.id,
          name: profile.name,
          designation: profile.designation,
          photoUrl: profile.photoUrl,
          role: profile.role,
        ));
      } else {
        final fetched = await ApiService.getCurrentUserProfile(token);
        if (fetched != null) await Storage.saveUserProfile(fetched);
      }
      if (!mounted) return;
      await Provider.of<TrackingService>(context, listen: false)
          .configureAuthenticatedSession(token: token, userId: userId?.toInt());
      await ensureNotificationPermissionReady(context);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
    } catch (e) {
      _showMsg(userFriendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOtp() async {
    if (_mobileController.text.trim().isEmpty) {
      _showMsg('Enter mobile number.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.sendOtp(_mobileController.text.trim());
      _showMsg('OTP sent.');
    } catch (e) {
      _showMsg(userFriendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_mobileController.text.trim().isEmpty ||
        _otpController.text.trim().isEmpty ||
        _newPasswordController.text.trim().isEmpty) {
      _showMsg('All fields are required.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.resetPassword(
        _mobileController.text.trim(),
        _otpController.text.trim(),
        _newPasswordController.text.trim(),
      );
      _showMsg('Password reset. Please log in.');
      setState(() => _isForgotMode = false);
    } catch (e) {
      _showMsg(userFriendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF060E1E),
              Color(0xFF0D1F4A),
              Color(0xFF1A2B7A),
              Color(0xFF7B1111),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.35, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Glow blobs
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF2563EB).withValues(alpha: 0.15),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: 180,
              left: -50,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFB91C1C).withValues(alpha: 0.18),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      // ── Logo
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37)
                                  .withValues(alpha: 0.35),
                              blurRadius: 40,
                              spreadRadius: 6,
                            ),
                            BoxShadow(
                              color: const Color(0xFF1D4ED8)
                                  .withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 2,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const AppLogo(
                          size: 130,
                          fit: BoxFit.contain,
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'TRINETRA RPF',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'RAILWAY PROTECTION FORCE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9.5,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Form card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        padding: const EdgeInsets.all(22),
                        child: _isForgotMode ? _forgotForm() : _loginForm(),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome Back',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 22),
        _glassField(
          controller: _cugController,
          hint: 'CUG Number',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        _glassField(
          controller: _passwordController,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          obscure: !_passwordVisible,
          suffix: IconButton(
            icon: Icon(
              _passwordVisible
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => setState(() => _isForgotMode = true),
            child: Text(
              'Forgot password?',
              style: TextStyle(
                color: Colors.redAccent.shade100,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _loginBtn('Login', _handleLogin),
      ],
    );
  }

  Widget _forgotForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _isForgotMode = false),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  size: 18, color: Colors.white70),
            ),
            const SizedBox(width: 8),
            const Text(
              'Reset Password',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'OTP will be sent to your registered number.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _glassField(
                controller: _mobileController,
                hint: 'Mobile Number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('OTP',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _glassField(
          controller: _otpController,
          hint: 'OTP Code',
          icon: Icons.sms_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        _glassField(
          controller: _newPasswordController,
          hint: 'New Password',
          icon: Icons.lock_outline_rounded,
          obscure: true,
        ),
        const SizedBox(height: 22),
        _loginBtn('Reset Password', _resetPassword),
      ],
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
      ),
    );
  }

  Widget _loginBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFFB91C1C)],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
