import '../config/app_config.dart';

class InspectionTaskPage {
  final int pendingCount;
  final int completeCount;
  final List<InspectionTask> tasks;
  final int currentPage;
  final int perPage;
  final int total;
  final int lastPage;
  final bool hasMore;

  const InspectionTaskPage({
    required this.pendingCount,
    required this.completeCount,
    required this.tasks,
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.lastPage,
    required this.hasMore,
  });

  factory InspectionTaskPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final counts = data['counts'] as Map<String, dynamic>? ?? const {};
    final pagination =
        data['pagination'] as Map<String, dynamic>? ?? const {};
    final rawTasks = data['tasks'] as List<dynamic>? ?? const [];

    return InspectionTaskPage(
      pendingCount: (counts['pending'] as num?)?.toInt() ?? 0,
      completeCount: (counts['complete'] as num?)?.toInt() ?? 0,
      tasks: rawTasks
          .whereType<Map>()
          .map((item) => InspectionTask.fromJson(item.cast<String, dynamic>()))
          .toList(),
      currentPage: (pagination['current_page'] as num?)?.toInt() ?? 1,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? rawTasks.length,
      total: (pagination['total'] as num?)?.toInt() ?? rawTasks.length,
      lastPage: (pagination['last_page'] as num?)?.toInt() ?? 1,
      hasMore: pagination['has_more'] == true,
    );
  }
}

class InspectionTask {
  final int id;
  final int? inspectionId;
  final String description;
  final String status;
  final String? photoUrl;
  final String? completionRemark;
  final String? createdAt;
  final String? completedAt;
  final int? pendingDays;
  final String? inspectionType;
  final int? postId;
  final String? postName;
  final String? inspectorName;
  final String? inspectorDesignation;
  final String? assignedByName;
  final String? assignedByDesignation;

  const InspectionTask({
    required this.id,
    required this.inspectionId,
    required this.description,
    required this.status,
    this.photoUrl,
    this.completionRemark,
    this.createdAt,
    this.completedAt,
    this.pendingDays,
    this.inspectionType,
    this.postId,
    this.postName,
    this.inspectorName,
    this.inspectorDesignation,
    this.assignedByName,
    this.assignedByDesignation,
  });

  bool get isPending => status.toLowerCase() == 'pending';

  factory InspectionTask.fromJson(Map<String, dynamic> json) {
    final inspection =
        json['inspection'] is Map ? (json['inspection'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final post = inspection['post'] is Map
        ? (inspection['post'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final inspector = inspection['inspector'] is Map
        ? (inspection['inspector'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final assignedBy = json['assigned_by'] is Map
        ? (json['assigned_by'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return InspectionTask(
      id: (json['id'] as num).toInt(),
      inspectionId: (json['inspection_id'] as num?)?.toInt(),
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      photoUrl: _resolvePhotoUrl(json['photo_url']),
      completionRemark: _cleanString(json['completion_remark']),
      createdAt: _cleanString(json['created_at']),
      completedAt: _cleanString(json['completed_at']),
      pendingDays: (json['pending_days'] as num?)?.toInt(),
      inspectionType: _cleanString(inspection['type']),
      postId: (post['id'] as num?)?.toInt(),
      postName: _cleanString(post['name']),
      inspectorName: _cleanString(inspector['name']),
      inspectorDesignation: _cleanString(inspector['designation']),
      assignedByName: _cleanString(assignedBy['name']),
      assignedByDesignation: _cleanString(assignedBy['designation']),
    );
  }

  static String? _cleanString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _resolvePhotoUrl(dynamic value) {
    final raw = _cleanString(value);
    if (raw == null) {
      return null;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final normalized = raw.startsWith('/') ? raw.substring(1) : raw;
    if (normalized.startsWith('public/')) {
      return '${AppConfig.publicBaseUrl}/$normalized';
    }
    if (normalized.startsWith('storage/')) {
      return '${AppConfig.publicBaseUrl}/public/$normalized';
    }
    return '${AppConfig.publicBaseUrl}/public/storage/$normalized';
  }
}
