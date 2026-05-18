import '../models/active_duty_geofence.dart';
import '../services/api_service.dart';
import '../utils/storage.dart';

class DutyResumeCandidate {
  final int deploymentId;
  final int dutyLogId;
  final Map<String, dynamic> detail;

  const DutyResumeCandidate({
    required this.deploymentId,
    required this.dutyLogId,
    required this.detail,
  });
}

class DutyResumeService {
  DutyResumeService._();

  static Future<DutyResumeCandidate?> findMountedDuty(
    String token, {
    int? preferredDeploymentId,
    int? preferredDutyLogId,
  }) async {
    if (preferredDeploymentId != null) {
      final preferred = await _validateMountedDuty(
        token,
        preferredDeploymentId,
        expectedLogId: preferredDutyLogId,
      );
      if (preferred != null) {
        return preferred;
      }
    }

    final duties = await ApiService.getDutyList(token);
    for (final item in duties) {
      if (item is! Map) {
        continue;
      }
      final ui = item['ui'] as Map? ?? const {};
      final deployment = item['deployment'] as Map? ?? const {};
      final deploymentId = (deployment['id'] as num?)?.toInt();
      final status = (ui['status'] as num?)?.toInt() ?? 0;
      if (deploymentId == null || status != 2) {
        continue;
      }

      final candidate = await _validateMountedDuty(token, deploymentId);
      if (candidate != null) {
        return candidate;
      }
    }

    return null;
  }

  static Future<DutyResumeCandidate?> _validateMountedDuty(
    String token,
    int deploymentId, {
    int? expectedLogId,
  }) async {
    final detail = await ApiService.getDutyDetail(token, deploymentId);
    final currentLog = detail['current_log'] as Map<String, dynamic>?;
    final currentLogId = (currentLog?['id'] as num?)?.toInt();

    if (!isMountedDutyActiveDetail(detail) ||
        currentLogId == null ||
        (expectedLogId != null && currentLogId != expectedLogId)) {
      return null;
    }

    final deployment =
        detail['deployment'] as Map<String, dynamic>? ?? const {};

    await Storage.saveActiveDutyGeofence(
      ActiveDutyGeofence.fromDeployment(deployment),
    );

    return DutyResumeCandidate(
      deploymentId: deploymentId,
      dutyLogId: currentLogId,
      detail: detail,
    );
  }

  static bool isMountedDutyActiveDetail(
    Map<String, dynamic> detail, {
    DateTime? now,
  }) {
    final currentLog = detail['current_log'] as Map<String, dynamic>?;
    final currentStatus = (currentLog?['status'] as num?)?.toInt() ?? 0;
    final currentLogId = (currentLog?['id'] as num?)?.toInt();
    final deployment =
        detail['deployment'] as Map<String, dynamic>? ?? const {};
    final dutyDate = deployment['duty_date']?.toString();
    final endTime = deployment['end_time']?.toString();
    final currentTime = now ?? DateTime.now();
    final todayKey =
        '${currentTime.year}-${currentTime.month.toString().padLeft(2, '0')}-${currentTime.day.toString().padLeft(2, '0')}';

    if (currentStatus != 2 || currentLogId == null || dutyDate != todayKey) {
      return false;
    }

    final dutyEndAt = _combineDutyDateAndTime(dutyDate, endTime);
    if (dutyEndAt != null && currentTime.isAfter(dutyEndAt)) {
      return false;
    }

    return true;
  }

  static DateTime? _combineDutyDateAndTime(String? dutyDate, String? time) {
    if (dutyDate == null || dutyDate.isEmpty || time == null || time.isEmpty) {
      return null;
    }

    final dateParts = dutyDate.split('-');
    final timeParts = time.split(':');
    if (dateParts.length != 3 || timeParts.length < 2) {
      return null;
    }

    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }

    return DateTime(year, month, day, hour, minute, second);
  }
}
