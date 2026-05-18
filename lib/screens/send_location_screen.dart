import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../utils/app_error_message.dart';
import '../utils/location_sampler.dart';
import '../utils/storage.dart';

class SendLocationScreen extends StatefulWidget {
  const SendLocationScreen({super.key});

  @override
  State<SendLocationScreen> createState() => _SendLocationScreenState();
}

class _SendLocationScreenState extends State<SendLocationScreen> {
  Position? _position;
  DateTime? _capturedAt;
  bool _loadingLocation = true;
  bool _sendingLocation = false;
  String? _errorText;
  String? _successText;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
      _errorText = null;
      _successText = null;
    });

    try {
      final position = await _getCurrentLocation();
      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
        _capturedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = userFriendlyErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  Future<void> _sendLocation() async {
    final token = await Storage.getToken();
    final position = _position;

    if (token == null || token.isEmpty) {
      _showMessage('Login session is missing. Please log in again and try.');
      return;
    }

    if (position == null) {
      _showMessage('Please fetch the current location first.');
      return;
    }

    setState(() {
      _sendingLocation = true;
      _successText = null;
    });

    try {
      final payload = await ApiService.sendHomeLocation(
        token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      if (!mounted) {
        return;
      }

      final item = payload['item'];
      final sentAt = item is Map ? item['sent_at']?.toString() : null;
      setState(() {
        _successText = sentAt == null || sentAt.trim().isEmpty
            ? 'Location was sent successfully.'
            : 'Location was sent successfully at $sentAt.';
      });
      _showMessage('Location sent successfully.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(userFriendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _sendingLocation = false;
        });
      }
    }
  }

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('GPS is turned off. Please enable location services first.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please allow it from Settings.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was not granted.');
    }

    return LocationSampler.getBestEffortPosition(
      perSampleTimeout: const Duration(seconds: 4),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  String _fmtDouble(double value, {int digits = 6}) {
    return value.toStringAsFixed(digits);
  }

  String _fmtAccuracy(double value) {
    return '${value.toStringAsFixed(1)} m';
  }

  String _fmtTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Location'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadingLocation ? null : _loadCurrentLocation,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      backgroundColor:
          isDark ? const Color(0xFF0B1F3A) : const Color(0xFFF4F6FA),
      body: RefreshIndicator(
        onRefresh: _loadCurrentLocation,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeroCard(isDark),
            const SizedBox(height: 14),
            _buildStatusCard(isDark),
            const SizedBox(height: 14),
            _buildLocationCard(isDark),
            if (_successText != null) ...[
              const SizedBox(height: 14),
              _buildSuccessCard(isDark),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _sendingLocation || _loadingLocation
                    ? null
                    : _sendLocation,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _sendingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _sendingLocation ? 'Sending...' : 'Send Current Location',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual Location Share',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isDark) {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    if (_loadingLocation) {
      icon = Icons.gps_fixed_rounded;
      color = Colors.blue;
      title = 'Fetching location';
      subtitle = 'Acquiring GPS signal...';
    } else if (_errorText != null) {
      icon = Icons.error_outline_rounded;
      color = Colors.redAccent;
      title = 'Location unavailable';
      subtitle = _errorText!;
    } else {
      icon = Icons.check_circle_outline_rounded;
      color = Colors.green;
      title = 'Location ready';
      subtitle = 'GPS coordinates captured.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(bool isDark) {
    final position = _position;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Location Details',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadingLocation ? null : _loadCurrentLocation,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (position == null)
            Text(
              'Coordinates are not available yet.',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _infoTile(
                  isDark: isDark,
                  label: 'Latitude',
                  value: _fmtDouble(position.latitude),
                ),
                _infoTile(
                  isDark: isDark,
                  label: 'Longitude',
                  value: _fmtDouble(position.longitude),
                ),
                _infoTile(
                  isDark: isDark,
                  label: 'Accuracy',
                  value: _fmtAccuracy(position.accuracy),
                ),
                _infoTile(
                  isDark: isDark,
                  label: 'Captured',
                  value: _capturedAt == null ? '-' : _fmtTime(_capturedAt!),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F2E1D) : const Color(0xFFEFFAF3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF16A34A).withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF16A34A),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _successText ?? '',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF166534),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required bool isDark,
    required String label,
    required String value,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
