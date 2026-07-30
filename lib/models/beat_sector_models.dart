import 'dart:convert';

class BeatSectorAccess {
  final bool canView;
  final bool canInspect;
  final bool canManageAssignedMaster;
  final bool canMapPolyline;

  const BeatSectorAccess({
    required this.canView,
    required this.canInspect,
    required this.canManageAssignedMaster,
    required this.canMapPolyline,
  });

  factory BeatSectorAccess.fromJson(Map<String, dynamic> json) {
    return BeatSectorAccess(
      canView: _asBool(json['can_view']),
      canInspect: _asBool(json['can_inspect']),
      canManageAssignedMaster: _asBool(
        json['can_manage_assigned_master'] ?? json['can_manage_master'],
      ),
      canMapPolyline: _asBool(json['can_map_polyline']),
    );
  }

  bool get canManageMaster => canManageAssignedMaster;

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase().trim();
    return text == 'true' || text == '1' || text == 'yes';
  }
}

class AppBootstrap {
  final List<String> allowedModules;
  final Map<String, BeatSectorAccess> moduleCapabilities;

  const AppBootstrap({
    required this.allowedModules,
    required this.moduleCapabilities,
  });

  factory AppBootstrap.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final rawModules = data['allowed_modules'] as List? ?? const [];
    final rawCaps = data['module_capabilities'] as Map? ?? const {};
    final caps = <String, BeatSectorAccess>{};
    rawCaps.forEach((key, value) {
      if (value is Map) {
        caps[key.toString()] =
            BeatSectorAccess.fromJson(value.cast<String, dynamic>());
      }
    });

    return AppBootstrap(
      allowedModules: rawModules.map((e) => e.toString()).toList(),
      moduleCapabilities: caps,
    );
  }

  bool get canViewBeatSector =>
      allowedModules.contains('beat_sector') &&
      (moduleCapabilities['beat_sector']?.canView ?? false);
}

class BeatSectorHomeCard {
  final String key;
  final String title;
  final String? subtitle;
  final bool visible;
  final int? count;

  const BeatSectorHomeCard({
    required this.key,
    required this.title,
    required this.visible,
    this.subtitle,
    this.count,
  });

  factory BeatSectorHomeCard.fromJson(Map<String, dynamic> json) {
    return BeatSectorHomeCard(
      key: (json['key'] ?? json['code'] ?? json['slug'] ?? json['title'] ?? '')
          .toString(),
      title: (json['title'] ?? json['label'] ?? 'Beat Sector').toString(),
      subtitle: json['subtitle']?.toString() ?? json['description']?.toString(),
      visible: BeatSectorAccess._asBool(json['visible'] ?? true),
      count: _asInt(json['count'] ?? json['value']),
    );
  }
}

class BeatSectorHomeData {
  final List<BeatSectorHomeCard> cards;
  final Map<String, dynamic> raw;

  const BeatSectorHomeData({required this.cards, required this.raw});

  factory BeatSectorHomeData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final rawCards = data['cards'] as List? ?? const [];
    return BeatSectorHomeData(
      cards: rawCards
          .whereType<Map>()
          .map((e) => BeatSectorHomeCard.fromJson(e.cast<String, dynamic>()))
          .where((card) => card.visible)
          .toList(),
      raw: data,
    );
  }
}

class BeatPoint {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime? capturedAt;

  const BeatPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (capturedAt != null)
          'captured_at': capturedAt!.toUtc().toIso8601String(),
      };

  factory BeatPoint.fromJson(Map<String, dynamic> json) {
    return BeatPoint(
      latitude: _asDouble(json['latitude'] ?? json['lat']) ?? 0,
      longitude: _asDouble(json['longitude'] ?? json['lng']) ?? 0,
      accuracy: _asDouble(json['accuracy']),
      capturedAt: DateTime.tryParse(json['captured_at']?.toString() ?? ''),
    );
  }
}

class BeatCapabilities {
  final bool canView;
  final bool canInspect;
  final bool canManageMaster;
  final bool canMapPolyline;

  const BeatCapabilities({
    required this.canView,
    required this.canInspect,
    required this.canManageMaster,
    required this.canMapPolyline,
  });

  factory BeatCapabilities.fromJson(Map<String, dynamic> json) {
    return BeatCapabilities(
      canView: BeatSectorAccess._asBool(json['can_view']),
      canInspect: BeatSectorAccess._asBool(json['can_inspect']),
      canManageMaster: BeatSectorAccess._asBool(json['can_manage_master']),
      canMapPolyline: BeatSectorAccess._asBool(json['can_map_polyline']),
    );
  }
}

class SectorBeat {
  final int id;
  final String name;
  final String code;
  final String sector;
  final String post;
  final String assignmentType;
  final String mappingState;
  final Map<String, int> masterCounts;
  final BeatCapabilities capabilities;
  final Map<String, dynamic> raw;

  const SectorBeat({
    required this.id,
    required this.name,
    required this.code,
    required this.sector,
    required this.post,
    required this.assignmentType,
    required this.mappingState,
    required this.masterCounts,
    required this.capabilities,
    required this.raw,
  });

  factory SectorBeat.fromJson(Map<String, dynamic> json) {
    final caps = json['capabilities'] is Map
        ? BeatCapabilities.fromJson(
            (json['capabilities'] as Map).cast<String, dynamic>())
        : const BeatCapabilities(
            canView: true,
            canInspect: false,
            canManageMaster: false,
            canMapPolyline: false,
          );
    final counts = <String, int>{};
    final rawCounts = json['master_counts'] ?? json['counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        counts[key.toString()] = _asInt(value) ?? 0;
      });
    }
    return SectorBeat(
      id: _asInt(json['id'] ?? json['sector_beat_id']) ?? 0,
      name: (json['name'] ?? json['beat_name'] ?? '-').toString(),
      code: (json['code'] ?? json['code_name'] ?? json['beat_code'] ?? '')
          .toString(),
      sector: _nestedName(json['sector'] ?? json['sector_name']),
      post: _nestedName(json['post'] ?? json['post_name']),
      assignmentType: (json['assignment_type'] ?? '').toString(),
      mappingState: (json['mapping_state'] ??
              json['map_status'] ??
              json['mapping_status'] ??
              '')
          .toString(),
      masterCounts: counts,
      capabilities: caps,
      raw: json,
    );
  }
}

class BeatPage {
  final List<SectorBeat> items;
  final int currentPage;
  final int lastPage;

  const BeatPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory BeatPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final list =
        (data['items'] ?? data['beats'] ?? data['data']) as List? ?? const [];
    final pagination = data['pagination'] is Map
        ? (data['pagination'] as Map).cast<String, dynamic>()
        : data;
    return BeatPage(
      items: list
          .whereType<Map>()
          .map((e) => SectorBeat.fromJson(e.cast<String, dynamic>()))
          .toList(),
      currentPage: _asInt(pagination['current_page']) ?? 1,
      lastPage: _asInt(pagination['last_page']) ?? 1,
    );
  }
}

class BeatMapping {
  final int bufferMeter;
  final List<BeatPoint> points;

  const BeatMapping({required this.bufferMeter, required this.points});

  factory BeatMapping.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final raw = data['points'] ?? data['polyline_points'] ?? data['mapping'];
    final points = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => BeatPoint.fromJson(e.cast<String, dynamic>()))
            .where((p) => p.latitude != 0 && p.longitude != 0)
            .toList()
        : <BeatPoint>[];
    return BeatMapping(
      bufferMeter: _asInt(data['buffer_meter'] ?? data['radius_meter']) ?? 50,
      points: points,
    );
  }
}

class BeatLookups {
  final List<Map<String, dynamic>> assetTypes;
  final List<Map<String, dynamic>> contactTypes;
  final List<Map<String, dynamic>> vulnerableTypes;
  final List<Map<String, dynamic>> categories;

  const BeatLookups({
    required this.assetTypes,
    required this.contactTypes,
    required this.vulnerableTypes,
    required this.categories,
  });

  factory BeatLookups.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return BeatLookups(
      assetTypes: _lookupList(data, const ['asset_types', 'assetTypes']),
      contactTypes: _lookupList(data, const [
        'contact_types',
        'contactTypes',
        'contact_type',
        'contactType',
      ]),
      vulnerableTypes: _lookupList(data, const [
        'vulnerable_types',
        'vulnerableTypes',
        'vulnerable_type',
        'vulnerableType',
      ]),
      categories: _listMap(data['categories'] ?? data['inspection_categories']),
    );
  }
}

List<Map<String, dynamic>> _lookupList(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final items = _listMap(data[key]);
    if (items.isNotEmpty) {
      return items;
    }
  }
  final lookups = data['lookups'];
  if (lookups is Map) {
    final nested = lookups.cast<String, dynamic>();
    for (final key in keys) {
      final items = _listMap(nested[key]);
      if (items.isNotEmpty) {
        return items;
      }
    }
  }
  return const [];
}

class MappingDraft {
  final int bufferMeter;
  final List<BeatPoint> points;

  const MappingDraft({required this.bufferMeter, required this.points});

  String toJsonString() => jsonEncode({
        'buffer_meter': bufferMeter,
        'points': points.map((p) => p.toJson()).toList(),
      });

  factory MappingDraft.fromJsonString(String? source) {
    if (source == null || source.isEmpty) {
      return const MappingDraft(bufferMeter: 50, points: []);
    }
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return MappingDraft(
        bufferMeter: _asInt(json['buffer_meter']) ?? 50,
        points: (json['points'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => BeatPoint.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
    } catch (_) {
      return const MappingDraft(bufferMeter: 50, points: []);
    }
  }
}

String _nestedName(dynamic value) {
  if (value is Map) {
    return (value['name'] ?? value['title'] ?? '').toString();
  }
  return value?.toString() ?? '';
}

List<Map<String, dynamic>> _listMap(dynamic value) {
  return (value as List? ?? const [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool hasMinimumDistinctMappingPoints(List<BeatPoint> points) {
  if (points.length < 2) return false;
  final first = points.first;
  return points.any((point) =>
      point.latitude != first.latitude || point.longitude != first.longitude);
}
