import 'package:flutter_test/flutter_test.dart';
import 'package:rpf_flutter/models/app_version_policy.dart';
import 'package:rpf_flutter/models/beat_sector_models.dart';
import 'package:rpf_flutter/screens/beat_sector_screen.dart';
import 'package:rpf_flutter/services/api_service.dart';

void main() {
  test('app version policy parses response and requires force update', () {
    final policy = AppVersionPolicy.fromJson({
      'status': 'success',
      'data': {
        'android': {
          'minimum_version_code': 2,
          'latest_version_code': 2,
          'force_update': true,
          'play_store_url':
              'https://play.google.com/store/apps/details?id=in.rpfwcr',
        }
      }
    });

    expect(policy.minimumVersionCode, 2);
    expect(policy.latestVersionCode, 2);
    expect(policy.forceUpdate, isTrue);
    expect(policy.playStoreUrl, contains('in.rpfwcr'));
    expect(policy.requiresUpdate(1), isTrue);
    expect(policy.requiresUpdate(2), isFalse);
  });

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

  test('inspection deployment model is null-safe and parses pagination', () {
    final page = InspectionDeploymentPage.fromJson({
      'status': 'success',
      'data': {
        'items': [
          {
            'id': 44,
            'scheduled_date': '2026-08-13',
            'status': 'pending',
            'instructions': null,
            'can_start': true,
            'can_resume': false,
            'inspection_id': null,
            'observations_count': null,
            'beat': {
              'id': 12,
              'name': 'Testing Beat',
              'code_name': 'BT-01',
              'sector': 'Sector-A',
              'post': 'Jabalpur Post',
            },
          }
        ],
        'current_page': 1,
        'per_page': 20,
        'total': 21,
        'last_page': 2,
        'has_more': true,
      }
    });

    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(page.items.first.id, 44);
    expect(page.items.first.beat.id, 12);
    expect(page.items.first.beat.code, 'BT-01');
    expect(page.items.first.instructions, '');
    expect(page.items.first.observationsCount, 0);
    expect(page.items.first.statusLabel, 'Pending');
  });

  test('deployment action rules follow backend flags', () {
    InspectionDeployment deployment({
      required String status,
      required bool canStart,
      required bool canResume,
      int? inspectionId,
    }) {
      return InspectionDeployment.fromJson({
        'id': 1,
        'scheduled_date': '2026-08-13',
        'status': status,
        'can_start': canStart,
        'can_resume': canResume,
        'inspection_id': inspectionId,
        'beat': {'id': 7, 'name': 'Beat A'},
      });
    }

    expect(
      deploymentActionLabel(
        deployment(status: 'pending', canStart: true, canResume: false),
      ),
      'Start',
    );
    expect(
      deploymentActionLabel(
        deployment(status: 'pending', canStart: false, canResume: false),
      ),
      isNull,
    );
    expect(
      deploymentActionLabel(
        deployment(
          status: 'in_progress',
          canStart: false,
          canResume: true,
          inspectionId: 55,
        ),
      ),
      'Resume',
    );
    expect(
      deploymentActionLabel(
        deployment(status: 'completed', canStart: false, canResume: false),
      ),
      isNull,
    );
    expect(
      deploymentActionLabel(
        deployment(status: 'missed', canStart: false, canResume: false),
      ),
      isNull,
    );
  });

  test('scheduled inspection start payload includes deployment and beat ids',
      () {
    expect(
      ApiService.buildStartBeatInspectionPayload(
        beatId: 12,
        deploymentId: 44,
      ),
      {'deployment_id': 44, 'sector_beat_id': 12},
    );
    expect(
      ApiService.buildStartBeatInspectionPayload(beatId: 12),
      {'sector_beat_id': 12},
    );
  });
}
