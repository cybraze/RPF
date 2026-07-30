import 'package:flutter_test/flutter_test.dart';
import 'package:rpf_flutter/models/beat_sector_models.dart';

void main() {
  test(
      'bootstrap allows Beat Sector only when module and capability are present',
      () {
    final denied = AppBootstrap.fromJson({
      'data': {
        'allowed_modules': ['beat_sector'],
        'module_capabilities': {
          'beat_sector': {'can_view': false}
        }
      }
    });
    expect(denied.canViewBeatSector, isFalse);

    final allowed = AppBootstrap.fromJson({
      'data': {
        'allowed_modules': ['beat_sector'],
        'module_capabilities': {
          'beat_sector': {'can_view': true}
        }
      }
    });
    expect(allowed.canViewBeatSector, isTrue);
  });

  test('alternate beat does not expose master or mapping actions', () {
    final beat = SectorBeat.fromJson({
      'id': 7,
      'name': 'BPL Yard',
      'assignment_type': 'alternate',
      'capabilities': {
        'can_view': true,
        'can_inspect': true,
        'can_manage_master': false,
        'can_map_polyline': false,
      }
    });

    expect(beat.capabilities.canInspect, isTrue);
    expect(beat.capabilities.canManageMaster, isFalse);
    expect(beat.capabilities.canMapPolyline, isFalse);
  });

  test('home cards use backend visible flags', () {
    final home = BeatSectorHomeData.fromJson({
      'data': {
        'cards': [
          {'key': 'assigned', 'title': 'My Assigned Beats', 'visible': true},
          {'key': 'master', 'title': 'Beat Master Data', 'visible': false},
        ]
      }
    });

    expect(home.cards.map((c) => c.key), ['assigned']);
  });

  test('mapping requires at least two different points', () {
    expect(
      hasMinimumDistinctMappingPoints([
        const BeatPoint(latitude: 23.1, longitude: 79.1),
      ]),
      isFalse,
    );
    expect(
      hasMinimumDistinctMappingPoints([
        const BeatPoint(latitude: 23.1, longitude: 79.1),
        const BeatPoint(latitude: 23.1, longitude: 79.1),
      ]),
      isFalse,
    );
    expect(
      hasMinimumDistinctMappingPoints([
        const BeatPoint(latitude: 23.1, longitude: 79.1),
        const BeatPoint(latitude: 23.2, longitude: 79.1),
      ]),
      isTrue,
    );
  });
}
