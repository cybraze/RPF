import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/beat_sector_models.dart';
import '../services/api_service.dart';
import '../utils/app_error_message.dart';
import '../utils/location_sampler.dart';
import '../utils/session_manager.dart';
import '../utils/storage.dart';

const _navy = Color(0xFF1A2B4A);
const _indigo = Color(0xFF3B5BDB);
const _green = Color(0xFF12B76A);
const _orange = Color(0xFFF79009);
const _red = Color(0xFFF04438);
const _bgLight = Color(0xFFF8FAFC);
const _textSec = Color(0xFF667085);
const _border = Color(0xFFE4E7EC);

class BeatSectorHomeScreen extends StatefulWidget {
  final BeatSectorHomeData? initialHome;

  const BeatSectorHomeScreen({super.key, this.initialHome});

  @override
  State<BeatSectorHomeScreen> createState() => _BeatSectorHomeScreenState();
}

class _BeatSectorHomeScreenState extends State<BeatSectorHomeScreen> {
  late Future<BeatSectorHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initialHome != null
        ? Future.value(widget.initialHome)
        : _loadHome();
  }

  Future<BeatSectorHomeData> _loadHome() async {
    final token = await _token();
    return ApiService.getBeatSectorHome(token);
  }

  void _reload() {
    setState(() {
      _future = _loadHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1B2E) : _bgLight,
      body: Column(
        children: [
          _Header(title: 'Beat Sector', onRefresh: _reload),
          Expanded(
            child: FutureBuilder<BeatSectorHomeData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingState(label: 'Loading Beat Sector...');
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    message: userFriendlyErrorMessage(snapshot.error ?? ""),
                    onRetry: _reload,
                  );
                }
                final cards = (snapshot.data?.cards ?? const [])
                    .where((card) => !_isAssignedBeatsCard(card))
                    .toList();
                final visibleCards = [
                  const BeatSectorHomeCard(
                    key: 'inspection_schedule',
                    title: 'Inspection Schedule',
                    subtitle: 'Date-wise inspection deployment',
                    visible: true,
                  ),
                  ...cards,
                ];
                if (visibleCards.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.dashboard_customize_outlined,
                    title: 'No Beat Sector cards available',
                    message: 'Your current assignment has no visible actions.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                  },
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.05,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: visibleCards.length,
                    itemBuilder: (_, index) {
                      final card = visibleCards[index];
                      return _HomeActionCard(
                        card: card,
                        onTap: () => _openCard(card),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isAssignedBeatsCard(BeatSectorHomeCard card) {
    final value = '${card.key} ${card.title}'.toLowerCase();
    return value.contains('assigned') || value.contains('my assigned');
  }

  void _openCard(BeatSectorHomeCard card) {
    final key = card.key.toLowerCase();
    if (key.contains('schedule') || key.contains('deployment')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BeatInspectionScheduleScreen()),
      );
      return;
    }
    if (key.contains('inspection') && key.contains('history')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BeatInspectionHistoryScreen()),
      );
      return;
    }
    if (key.contains('inspection')) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const BeatListScreen(mode: 'inspect')),
      );
      return;
    }
    if (key.contains('master')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BeatMasterLauncherScreen()),
      );
      return;
    }
    if (key.contains('map')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BeatMapLauncherScreen()),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BeatListScreen()),
    );
  }
}

class BeatInspectionScheduleScreen extends StatefulWidget {
  const BeatInspectionScheduleScreen({super.key});

  @override
  State<BeatInspectionScheduleScreen> createState() =>
      _BeatInspectionScheduleScreenState();
}

class _BeatInspectionScheduleScreenState
    extends State<BeatInspectionScheduleScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final List<InspectionDeployment> _items = [];
  InspectionDeploymentStatus _status = InspectionDeploymentStatus.all;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _actionRunning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(reset: true, quiet: true);
    }
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (_scroll.position.extentAfter < 320) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset, bool quiet = false}) async {
    if (reset) {
      _page = 1;
      if (!quiet) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final token = await _token();
      final page = await ApiService.getInspectionDeployments(
        token,
        status: _status,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page = page.currentPage + 1;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFriendlyErrorMessage(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() => _load(reset: true, quiet: true);

  void _changeStatus(InspectionDeploymentStatus status) {
    if (_status == status) return;
    setState(() => _status = status);
    _load(reset: true);
  }

  Future<void> _startOrResume(InspectionDeployment item) async {
    if (_actionRunning) return;
    if (deploymentActionLabel(item) == null) return;
    if (!await _hasNetwork()) {
      _snack('No connection. Scheduled inspection cannot start offline.', true);
      return;
    }
    setState(() => _actionRunning = true);
    try {
      int? inspectionId = item.inspectionId;
      if (item.canStart) {
        final token = await _token();
        final started = await ApiService.startBeatInspection(
          token,
          item.beat.id,
          deploymentId: item.id,
        );
        final inspection = started['inspection'] is Map
            ? (started['inspection'] as Map).cast<String, dynamic>()
            : started;
        inspectionId = _asInt(inspection['id']);
      }
      if (inspectionId == null) throw Exception('Inspection id missing.');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BeatInspectionScreen(
            beat: item.beat,
            inspectionId: inspectionId,
            deploymentId: item.id,
            onFinished: () => _load(reset: true, quiet: true),
          ),
        ),
      );
      await _load(reset: true, quiet: true);
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<bool> _hasNetwork() async {
    try {
      final result =
          await InternetAddress.lookup(Uri.parse(ApiService.baseUrl).host)
              .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1B2E) : _bgLight,
      body: Column(
        children: [
          _Header(title: 'Inspection Schedule', onRefresh: () => _refresh()),
          _ScheduleFilters(selected: _status, onChanged: _changeStatus),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const _LoadingState(label: 'Loading inspection schedule...');
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorState(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No scheduled inspections',
              message: 'Assigned inspections will appear here.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return _DeploymentCard(
            item: item,
            busy: _actionRunning,
            onAction: () => _startOrResume(item),
          );
        },
      ),
    );
  }
}

class _ScheduleFilters extends StatelessWidget {
  final InspectionDeploymentStatus selected;
  final ValueChanged<InspectionDeploymentStatus> onChanged;

  const _ScheduleFilters({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: isDark ? const Color(0xFF0D1B2E) : _bgLight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: InspectionDeploymentStatus.values.map((status) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selected == status,
                label: Text(status.label),
                onSelected: (_) => onChanged(status),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DeploymentCard extends StatelessWidget {
  final InspectionDeployment item;
  final bool busy;
  final VoidCallback onAction;

  const _DeploymentCard({
    required this.item,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final action = deploymentActionLabel(item);
    return _Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _formatScheduleDate(item.scheduledDate),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusChip(status: item.status, label: item.statusLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.beat.code.isEmpty
                ? item.beat.name
                : '${item.beat.name} (${item.beat.code})',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (item.beat.sector.isNotEmpty)
                _InfoChip(
                    icon: Icons.grid_view_outlined, label: item.beat.sector),
              if (item.beat.post.isNotEmpty)
                _InfoChip(
                    icon: Icons.apartment_outlined, label: item.beat.post),
              _InfoChip(
                icon: Icons.notes_outlined,
                label: '${item.observationsCount} observations',
              ),
            ],
          ),
          if (item.instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.instructions, style: const TextStyle(color: _textSec)),
          ],
          if (action != null) ...[
            const SizedBox(height: 12),
            _FullButton(
              icon: item.canResume
                  ? Icons.play_circle_outline
                  : Icons.flag_outlined,
              label: busy ? 'Please wait...' : action,
              onPressed: busy ? null : onAction,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;

  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = _deploymentStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class BeatMasterLauncherScreen extends StatefulWidget {
  const BeatMasterLauncherScreen({super.key});

  @override
  State<BeatMasterLauncherScreen> createState() =>
      _BeatMasterLauncherScreenState();
}

class _BeatMasterLauncherScreenState extends State<BeatMasterLauncherScreen> {
  late Future<BeatPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<BeatPage> _load() async {
    final token = await _token();
    return ApiService.getSectorBeats(token);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BeatPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Column(
              children: [
                _Header(title: 'Beat Master Data'),
                Expanded(child: _LoadingState(label: 'Loading beat master...')),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Column(
              children: [
                const _Header(title: 'Beat Master Data'),
                Expanded(
                  child: _ErrorState(
                    message: userFriendlyErrorMessage(snapshot.error ?? ''),
                    onRetry: () => setState(() => _future = _load()),
                  ),
                ),
              ],
            ),
          );
        }
        final manageable = (snapshot.data?.items ?? const [])
            .where((beat) => beat.capabilities.canManageMaster)
            .toList();
        if (manageable.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BeatMasterScreen(beat: manageable.first),
              ),
            );
          });
          return const Scaffold(
            body: Column(
              children: [
                _Header(title: 'Beat Master Data'),
                Expanded(child: _LoadingState(label: 'Opening master data...')),
              ],
            ),
          );
        }
        return const BeatListScreen(mode: 'master');
      },
    );
  }
}

class BeatMapLauncherScreen extends StatefulWidget {
  const BeatMapLauncherScreen({super.key});

  @override
  State<BeatMapLauncherScreen> createState() => _BeatMapLauncherScreenState();
}

class _BeatMapLauncherScreenState extends State<BeatMapLauncherScreen> {
  late Future<BeatPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<BeatPage> _load() async {
    final token = await _token();
    return ApiService.getSectorBeats(token);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BeatPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Column(
              children: [
                _Header(title: 'Map My Beat'),
                Expanded(child: _LoadingState(label: 'Loading beats...')),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Column(
              children: [
                const _Header(title: 'Map My Beat'),
                Expanded(
                  child: _ErrorState(
                    message: userFriendlyErrorMessage(snapshot.error ?? ''),
                    onRetry: () => setState(() => _future = _load()),
                  ),
                ),
              ],
            ),
          );
        }
        final mappable = (snapshot.data?.items ?? const [])
            .where((beat) => beat.capabilities.canMapPolyline)
            .toList();
        if (mappable.length == 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BeatMappingScreen(beat: mappable.first),
              ),
            );
          });
          return const Scaffold(
            body: Column(
              children: [
                _Header(title: 'Map My Beat'),
                Expanded(child: _LoadingState(label: 'Opening map...')),
              ],
            ),
          );
        }
        return const BeatListScreen(mode: 'map');
      },
    );
  }
}

class BeatListScreen extends StatefulWidget {
  final String mode;

  const BeatListScreen({super.key, this.mode = 'view'});

  @override
  State<BeatListScreen> createState() => _BeatListScreenState();
}

class _BeatListScreenState extends State<BeatListScreen> {
  final _scroll = ScrollController();
  final List<SectorBeat> _beats = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 180) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _lastPage = 1;
      });
    }
    try {
      final token = await _token();
      final page = await ApiService.getSectorBeats(token, page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) _beats.clear();
        _beats.addAll(page.items);
        _lastPage = page.lastPage;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userFriendlyErrorMessage(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _lastPage) return;
    setState(() {
      _loadingMore = true;
      _page += 1;
    });
    await _load(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D1B2E)
          : _bgLight,
      body: Column(
        children: [
          _Header(title: _title, onRefresh: () => _load(reset: true)),
          Expanded(
            child: Builder(
              builder: (_) {
                if (_loading) {
                  return const _LoadingState(
                      label: 'Loading assigned beats...');
                }
                if (_error != null) {
                  return _ErrorState(
                    message: _error!,
                    onRetry: () => _load(reset: true),
                  );
                }
                if (_beats.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.route_outlined,
                    title: 'No assigned beats',
                    message: 'Beat assignments will appear here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _beats.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index >= _beats.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final beat = _beats[index];
                      return _BeatCard(
                        beat: beat,
                        mode: widget.mode,
                        onTap: () => _openBeat(beat),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String get _title {
    switch (widget.mode) {
      case 'map':
        return 'Map My Beat';
      case 'master':
        return 'Beat Master Data';
      case 'inspect':
        return 'Beat Inspection';
      default:
        return 'My Assigned Beats';
    }
  }

  void _openBeat(SectorBeat beat) {
    if (widget.mode == 'map' && beat.capabilities.canMapPolyline) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BeatMappingScreen(beat: beat)),
      ).then((_) => _load(reset: true));
      return;
    }
    if (widget.mode == 'master') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BeatMasterScreen(beat: beat)),
      );
      return;
    }
    if (widget.mode == 'inspect' && beat.capabilities.canInspect) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BeatInspectionScreen(beat: beat)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BeatDetailScreen(beat: beat)),
    );
  }
}

class BeatDetailScreen extends StatefulWidget {
  final SectorBeat beat;

  const BeatDetailScreen({super.key, required this.beat});

  @override
  State<BeatDetailScreen> createState() => _BeatDetailScreenState();
}

class _BeatDetailScreenState extends State<BeatDetailScreen> {
  late Future<_BeatDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BeatDetailData> _load() async {
    final token = await _token();
    final detail = await ApiService.getSectorBeatDetail(token, widget.beat.id);
    BeatMapping? mapping;
    try {
      mapping = await ApiService.getBeatMapping(token, widget.beat.id);
    } catch (_) {}
    return _BeatDetailData(detail, mapping);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D1B2E)
          : _bgLight,
      body: Column(
        children: [
          _Header(
              title: 'Beat Details',
              onRefresh: () {
                setState(() => _future = _load());
              }),
          Expanded(
            child: FutureBuilder<_BeatDetailData>(
              future: _future,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingState(label: 'Loading beat...');
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    message: userFriendlyErrorMessage(snapshot.error ?? ""),
                    onRetry: () => setState(() => _future = _load()),
                  );
                }
                final beat = snapshot.data?.beat ?? widget.beat;
                final mapping = snapshot.data?.mapping;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _BeatCard(beat: beat, mode: 'view', onTap: () {}),
                    const SizedBox(height: 12),
                    if (mapping != null)
                      _PolylinePreview(points: mapping.points)
                    else
                      const _EmptyState(
                        icon: Icons.map_outlined,
                        title: 'No mapping available',
                        message: 'Polyline will appear after mapping is saved.',
                      ),
                    const SizedBox(height: 12),
                    if (beat.capabilities.canMapPolyline)
                      _FullButton(
                        icon: Icons.edit_location_alt_outlined,
                        label: 'Map Beat',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BeatMappingScreen(beat: beat),
                          ),
                        ),
                      ),
                    if (beat.capabilities.canManageMaster ||
                        beat.capabilities.canView) ...[
                      const SizedBox(height: 10),
                      _FullButton(
                        icon: Icons.dataset_outlined,
                        label: 'Master Data',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BeatMasterScreen(beat: beat),
                          ),
                        ),
                      ),
                    ],
                    if (beat.capabilities.canInspect) ...[
                      const SizedBox(height: 10),
                      _FullButton(
                        icon: Icons.fact_check_outlined,
                        label: 'Start Inspection',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BeatInspectionScreen(beat: beat),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BeatMappingScreen extends StatefulWidget {
  final SectorBeat beat;

  const BeatMappingScreen({super.key, required this.beat});

  @override
  State<BeatMappingScreen> createState() => _BeatMappingScreenState();
}

class _BeatMappingScreenState extends State<BeatMappingScreen> {
  final _map = MapController();
  final List<BeatPoint> _points = [];
  StreamSubscription<Position>? _sub;
  int _bufferMeter = 50;
  bool _recording = false;
  bool _saving = false;
  double? _accuracy;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final draft = await Storage.getBeatMappingDraft(widget.beat.id);
    if (draft.points.isNotEmpty && mounted) {
      final useDraft = await _confirm(
        'Unsaved Draft',
        'A saved mapping draft is available. Continue with it?',
      );
      if (useDraft == true) {
        setState(() {
          _bufferMeter = draft.bufferMeter;
          _points.addAll(draft.points);
        });
        return;
      }
    }
    try {
      final token = await _token();
      final mapping = await ApiService.getBeatMapping(token, widget.beat.id);
      if (!mounted) return;
      setState(() {
        _bufferMeter = mapping.bufferMeter;
        _points
          ..clear()
          ..addAll(mapping.points);
      });
    } catch (_) {}
  }

  Future<void> _start() async {
    final ok = await _ensureLocationReady();
    if (!ok) return;
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSampler.trackingSettings(),
    ).listen(_addPosition, onError: (e) {
      setState(() => _message = userFriendlyErrorMessage(e));
    });
    setState(() {
      _recording = true;
      _message = null;
    });
  }

  Future<void> _pause() async {
    await _sub?.cancel();
    _sub = null;
    setState(() => _recording = false);
    await _saveDraft();
  }

  void _addPosition(Position pos) {
    final point = BeatPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      capturedAt: pos.timestamp,
    );
    final last = _points.isEmpty ? null : _points.last;
    if (last != null &&
        Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              point.latitude,
              point.longitude,
            ) <
            2) {
      return;
    }
    setState(() {
      _points.add(point);
      _accuracy = pos.accuracy;
    });
    _saveDraft();
  }

  Future<void> _addManualPoint() async {
    final ok = await _ensureLocationReady();
    if (!ok) return;
    final pos = await LocationSampler.getBestEffortPosition(
      perSampleTimeout: const Duration(seconds: 20),
    );
    _addPosition(pos);
  }

  Future<void> _saveDraft() {
    return Storage.saveBeatMappingDraft(
      widget.beat.id,
      MappingDraft(bufferMeter: _bufferMeter, points: _points),
    );
  }

  Future<void> _finish() async {
    if (!hasMinimumDistinctMappingPoints(_points)) {
      _snack('Add at least two different route points.', true);
      return;
    }
    final ok = await _confirm('Save Mapping', 'Overwrite beat mapping now?');
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _pause();
      final token = await _token();
      await ApiService.saveBeatMapping(
        token: token,
        beatId: widget.beat.id,
        bufferMeter: _bufferMeter,
        points: _points,
      );
      await Storage.clearBeatMappingDraft(widget.beat.id);
      if (mounted) {
        _snack('Mapping saved successfully.', false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    final ok = await _confirm('Discard Draft', 'Remove unsaved route points?');
    if (ok != true) return;
    await _pause();
    await Storage.clearBeatMappingDraft(widget.beat.id);
    setState(() => _points.clear());
  }

  @override
  Widget build(BuildContext context) {
    final poor = (_accuracy ?? 0) > 25;
    return Scaffold(
      body: Column(
        children: [
          const _Header(title: 'Map My Beat'),
          Expanded(child: _PolylinePreview(points: _points, controller: _map)),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${_points.length} points')),
                    Text('Buffer $_bufferMeter m'),
                  ],
                ),
                Slider(
                  value: _bufferMeter.toDouble(),
                  min: 10,
                  max: 500,
                  divisions: 49,
                  label: '$_bufferMeter m',
                  onChanged: (v) {
                    setState(() => _bufferMeter = v.round());
                    _saveDraft();
                  },
                ),
                if (poor)
                  const _Notice(
                    color: _orange,
                    text: 'GPS accuracy is poor. Wait for a better signal.',
                  ),
                if (_message != null) _Notice(color: _red, text: _message!),
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        icon: _recording ? Icons.pause : Icons.play_arrow,
                        label: _recording ? 'Pause' : 'Start',
                        onPressed: _recording ? _pause : _start,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        icon: Icons.add_location_alt_outlined,
                        label: 'Point',
                        onPressed: _addManualPoint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        icon: Icons.delete_outline,
                        label: 'Discard',
                        onPressed: _discard,
                        danger: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _FullButton(
                  icon: Icons.check_circle_outline,
                  label: _saving ? 'Saving...' : 'Finish Recording',
                  onPressed: _saving ? null : _finish,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _points.isEmpty
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                final p = _points.last;
                _map.move(LatLng(p.latitude, p.longitude), 17);
              },
              child: const Icon(Icons.my_location),
            ),
    );
  }
}

class BeatMasterScreen extends StatefulWidget {
  final SectorBeat beat;

  const BeatMasterScreen({super.key, required this.beat});

  @override
  State<BeatMasterScreen> createState() => _BeatMasterScreenState();
}

class _BeatMasterScreenState extends State<BeatMasterScreen> {
  BeatLookups? _lookups;

  static const _types = [
    _MasterType('villages', 'Villages', Icons.location_city_outlined),
    _MasterType('assets', 'Assets', Icons.account_tree_outlined),
    _MasterType('contacts', 'Contacts', Icons.contacts_outlined),
    _MasterType(
      'vulnerable-spots',
      'Vulnerable Spots',
      Icons.warning_amber_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final token = await _token();
      final lookups = await ApiService.getBeatLookups(token);
      if (mounted) setState(() => _lookups = lookups);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D1B2E)
          : _bgLight,
      body: Column(
        children: [
          const _Header(title: 'Beat Master Data'),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemCount: _types.length,
              itemBuilder: (_, index) {
                final type = _types[index];
                final count = _countFor(type.key);
                return _Card(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _MasterTypeScreen(
                          beat: widget.beat,
                          type: type.key,
                          title: type.title,
                          lookups: _lookups,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(type.icon, color: _indigo, size: 30),
                        const Spacer(),
                        Text(
                          type.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        _Badge(label: count.toString()),
                        const SizedBox(height: 6),
                        Text(
                          widget.beat.capabilities.canManageMaster
                              ? 'View, add, edit, delete'
                              : 'View only',
                          style: const TextStyle(color: _textSec, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _countFor(String type) {
    final counts = widget.beat.masterCounts;
    return counts[type] ??
        counts[type.replaceAll('-', '_')] ??
        counts[type.replaceAll('-spots', '_spots')] ??
        0;
  }
}

class _MasterType {
  final String key;
  final String title;
  final IconData icon;

  const _MasterType(this.key, this.title, this.icon);
}

class _MasterTypeScreen extends StatelessWidget {
  final SectorBeat beat;
  final String type;
  final String title;
  final BeatLookups? lookups;

  const _MasterTypeScreen({
    required this.beat,
    required this.type,
    required this.title,
    required this.lookups,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Header(title: title),
          Expanded(
            child: _MasterList(
              beat: beat,
              type: type,
              lookups: lookups,
            ),
          ),
        ],
      ),
    );
  }
}

class BeatInspectionScreen extends StatefulWidget {
  final SectorBeat beat;
  final int? inspectionId;
  final int? deploymentId;
  final VoidCallback? onFinished;

  const BeatInspectionScreen({
    super.key,
    required this.beat,
    this.inspectionId,
    this.deploymentId,
    this.onFinished,
  });

  @override
  State<BeatInspectionScreen> createState() => _BeatInspectionScreenState();
}

class _BeatInspectionScreenState extends State<BeatInspectionScreen> {
  final _remark = TextEditingController();
  final _picker = ImagePicker();
  Map<String, dynamic>? _inspection;
  BeatLookups? _lookups;
  Map<String, dynamic>? _category;
  File? _attachment;
  bool _loading = true;
  bool _saving = false;
  bool _finishing = false;
  String? _error;
  List<Map<String, dynamic>> _previousObservations = const [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _token();
      final started = widget.inspectionId == null
          ? await ApiService.startBeatInspection(
              token,
              widget.beat.id,
              deploymentId: widget.deploymentId,
            )
          : <String, dynamic>{'id': widget.inspectionId};
      final inspection = started['inspection'] is Map
          ? (started['inspection'] as Map).cast<String, dynamic>()
          : started;
      final id = _asInt(inspection['id']);
      final detail = id == null
          ? inspection
          : await ApiService.getBeatInspection(token, id);
      final lookups = await ApiService.getBeatLookups(token);
      final previous = await ApiService.getBeatInspections(token);
      final previousObservations =
          await _loadPreviousObservations(token, previous, id);
      if (!mounted) return;
      setState(() {
        _inspection = detail;
        _lookups = lookups;
        _previousObservations = previousObservations;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFriendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (file != null && mounted) setState(() => _attachment = File(file.path));
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _attachment = File(path));
  }

  Future<void> _addObservation() async {
    if (_category == null) {
      _snack('Select category.', true);
      return;
    }
    if (_remark.text.trim().isEmpty) {
      _snack('Enter remark.', true);
      return;
    }
    setState(() => _saving = true);
    try {
      final id = _inspectionId;
      if (id == null) throw Exception('Inspection id missing.');
      final token = await _token();
      final pos = await _currentPosition();
      await ApiService.addBeatInspectionItem(
        token: token,
        inspectionId: id,
        categoryId: _asInt(_category!['id'])!,
        remark: _remark.text.trim(),
        latitude: pos.latitude,
        longitude: pos.longitude,
        locationAccuracy: pos.accuracy,
        capturedAt: DateTime.now(),
        attachmentPath: _attachment?.path,
      );
      _remark.clear();
      setState(() {
        _attachment = null;
        _category = null;
      });
      await _refreshDetail();
      if (mounted) _snack('Observation added.', false);
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshDetail() async {
    final id = _inspectionId;
    if (id == null) return;
    final token = await _token();
    final detail = await ApiService.getBeatInspection(token, id);
    if (mounted) setState(() => _inspection = detail);
  }

  Future<void> _openAttachment(String source) async {
    final url = _attachmentUri(source);
    if (url == null) {
      _snack('Attachment link not available.', true);
      return;
    }
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      _snack('Unable to open attachment.', true);
    }
  }

  Future<void> _finish() async {
    if (_items.isEmpty) {
      _snack('Add at least one observation first.', true);
      return;
    }
    setState(() => _finishing = true);
    try {
      final id = _inspectionId;
      if (id == null) throw Exception('Inspection id missing.');
      final token = await _token();
      await ApiService.finishBeatInspection(token, id);
      if (mounted) {
        _snack('Inspection completed.', false);
        widget.onFinished?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  bool _isSameBeatInspection(Map<String, dynamic> item) {
    final beatId = _asInt(
      item['sector_beat_id'] ??
          item['beat_id'] ??
          (item['beat'] is Map ? (item['beat'] as Map)['id'] : null) ??
          (item['sector_beat'] is Map
              ? (item['sector_beat'] as Map)['id']
              : null),
    );
    if (beatId != null) return beatId == widget.beat.id;
    final beatName = (item['beat_name'] ??
            item['sector_beat_name'] ??
            (item['beat'] is Map ? (item['beat'] as Map)['name'] : null) ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return beatName.isNotEmpty && beatName == widget.beat.name.toLowerCase();
  }

  Future<List<Map<String, dynamic>>> _loadPreviousObservations(
    String token,
    List<Map<String, dynamic>> inspections,
    int? currentInspectionId,
  ) async {
    final observations = <Map<String, dynamic>>[];
    final beatHistory = inspections.where((item) {
      final inspectionId = _asInt(item['id']);
      return inspectionId != currentInspectionId && _isSameBeatInspection(item);
    }).toList();

    for (final inspection in beatHistory.take(5)) {
      var detail = inspection;
      var items = _inspectionItems(detail);
      final inspectionId = _asInt(inspection['id']);
      if (items.isEmpty && inspectionId != null) {
        detail = await ApiService.getBeatInspection(token, inspectionId);
        items = _inspectionItems(detail);
      }
      final inspectionDate = _cleanDisplay(
        detail['completed_at'] ?? detail['started_at'] ?? detail['created_at'],
      );
      observations.addAll(
        items.map((item) {
          final copy = Map<String, dynamic>.from(item);
          copy.putIfAbsent('captured_at', () => inspectionDate);
          return copy;
        }),
      );
      if (observations.length >= 5) break;
    }

    return observations.take(5).toList();
  }

  int? get _inspectionId {
    final data = _inspection;
    if (data == null) return null;
    return _asInt(data['id'] ?? (data['inspection'] as Map?)?['id']);
  }

  List<Map<String, dynamic>> get _items {
    final data = _inspection ?? const {};
    return _inspectionItems(data);
  }

  List<Map<String, dynamic>> _inspectionItems(Map<String, dynamic> data) {
    final inspection = data['inspection'] is Map
        ? (data['inspection'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final raw = data['items'] ??
        data['observations'] ??
        data['inspection_items'] ??
        inspection['items'] ??
        inspection['observations'] ??
        inspection['inspection_items'];
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _Header(title: 'Beat Inspection'),
          Expanded(
            child: Builder(builder: (_) {
              if (_loading) {
                return const _LoadingState(label: 'Starting inspection...');
              }
              if (_error != null) {
                return _ErrorState(message: _error!, onRetry: _start);
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New Observation',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        _LookupDropdown(
                          label: 'Category',
                          value: _category,
                          items: _lookups?.categories ?? const [],
                          onChanged: (v) => setState(() => _category = v),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _remark,
                          maxLines: 3,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF101828),
                          ),
                          decoration: _themedInput(context, 'Remark'),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Image'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickPdf,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('PDF'),
                            ),
                          ],
                        ),
                        if (_attachment != null) ...[
                          const SizedBox(height: 8),
                          _Notice(
                            color: _indigo,
                            text: _attachment!.path
                                .split(Platform.pathSeparator)
                                .last,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _FullButton(
                          icon: Icons.cloud_upload_outlined,
                          label: _saving ? 'Uploading...' : 'Add Observation',
                          onPressed: _saving ? null : _addObservation,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Observations (${_items.length})',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (_items.isEmpty)
                          const Text('No observations added yet.',
                              style: TextStyle(color: _textSec))
                        else
                          ..._items.map(
                            (item) => _ObservationTile(
                              item: item,
                              onOpenAttachment: _openAttachment,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FullButton(
                    icon: Icons.done_all,
                    label: _finishing ? 'Finishing...' : 'Finish Inspection',
                    onPressed: _finishing ? null : _finish,
                  ),
                  const SizedBox(height: 12),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Previous Observations On This Beat',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (_previousObservations.isEmpty)
                          const Text('No previous observations found.',
                              style: TextStyle(color: _textSec))
                        else
                          ..._previousObservations.map(
                            (item) => _ObservationTile(
                              item: item,
                              onOpenAttachment: _openAttachment,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ObservationTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ValueChanged<String> onOpenAttachment;

  const _ObservationTile({required this.item, required this.onOpenAttachment});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF101828);
    final secondaryColor = isDark ? Colors.white70 : _textSec;
    final category = _observationCategory(item);
    final remark = _cleanDisplay(
      item['remark'] ?? item['remarks'] ?? item['note'] ?? item['description'],
    );
    final capturedAt = _cleanDisplay(
      item['captured_at'] ?? item['created_at'] ?? item['updated_at'],
    );
    final attachment = _observationAttachment(item);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : _bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notes_outlined, color: _indigo, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  category.isEmpty ? 'Observation' : category,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (remark.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              remark,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: titleColor, height: 1.25),
            ),
          ],
          if (capturedAt.isNotEmpty) ...[
            const SizedBox(height: 6),
            _InfoChip(
              icon: Icons.schedule_outlined,
              label: _formatObservationTime(capturedAt),
            ),
          ],
          if (attachment != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenAttachment(attachment.source),
                icon: Icon(
                  attachment.isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  size: 16,
                ),
                label: Text('View ${attachment.isPdf ? 'PDF' : 'Attachment'}'),
                style: TextButton.styleFrom(
                  foregroundColor: _indigo,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ] else if (remark.isEmpty) ...[
            Text('No remark found.', style: TextStyle(color: secondaryColor)),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white70 : _textSec),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : _textSec,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentLink {
  final String source;
  final bool isPdf;

  const _AttachmentLink({required this.source, required this.isPdf});
}

String _observationCategory(Map<String, dynamic> item) {
  return _cleanDisplay(
    item['category_name'] ??
        item['inspection_category_name'] ??
        item['category_title'] ??
        item['category'],
  );
}

_AttachmentLink? _observationAttachment(Map<String, dynamic> item) {
  final raw = item['attachment_url'] ??
      item['attachment_path'] ??
      item['attachment'] ??
      item['file_url'] ??
      item['file_path'] ??
      item['photo_url'] ??
      item['image_url'] ??
      item['document_url'] ??
      item['media_url'];
  final source = _attachmentSource(raw);
  if (source.isEmpty) return null;
  final lower = source.toLowerCase();
  return _AttachmentLink(
    source: source,
    isPdf: lower.contains('.pdf') || lower.contains('pdf'),
  );
}

String _attachmentSource(dynamic raw) {
  if (raw == null) return '';
  if (raw is Map) {
    return _cleanDisplay(
      raw['url'] ??
          raw['full_url'] ??
          raw['path'] ??
          raw['file_url'] ??
          raw['attachment_url'],
    );
  }
  return _cleanDisplay(raw);
}

Uri? _attachmentUri(String source) {
  final value = source.trim();
  if (value.isEmpty) return null;
  final direct = Uri.tryParse(value);
  if (direct != null && direct.hasScheme) return direct;
  final base = Uri.tryParse(ApiService.baseUrl);
  if (base == null) return null;
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  if (value.startsWith('/')) return Uri.tryParse(origin + value);
  return Uri.tryParse('${ApiService.baseUrl}/$value');
}

String _cleanDisplay(dynamic value) {
  if (value == null) return '';
  if (value is Map) {
    return _cleanDisplay(
      value['name'] ??
          value['title'] ??
          value['label'] ??
          value['value'] ??
          value['description'],
    );
  }
  if (value is List) {
    return value.map(_cleanDisplay).where((e) => e.isNotEmpty).join(', ');
  }
  return value.toString().trim();
}

String _formatObservationTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day-$month-${local.year} $hour:$minute';
}

String _formatScheduleDate(DateTime? value) {
  if (value == null) return '-';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day-$month-${value.year}';
}

String? deploymentActionLabel(InspectionDeployment item) {
  if (item.canStart) return 'Start';
  if (item.canResume && item.inspectionId != null) return 'Resume';
  return null;
}

Color _deploymentStatusColor(String status) {
  switch (status) {
    case 'pending':
      return _orange;
    case 'in_progress':
      return _indigo;
    case 'completed':
      return _green;
    case 'missed':
      return _red;
    default:
      return _textSec;
  }
}

class BeatInspectionHistoryScreen extends StatefulWidget {
  const BeatInspectionHistoryScreen({super.key});

  @override
  State<BeatInspectionHistoryScreen> createState() =>
      _BeatInspectionHistoryScreenState();
}

class _BeatInspectionHistoryScreenState
    extends State<BeatInspectionHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await _token();
    return ApiService.getBeatInspections(token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Header(
              title: 'Inspection History',
              onRefresh: () {
                setState(() => _future = _load());
              }),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingState(label: 'Loading inspections...');
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    message: userFriendlyErrorMessage(snapshot.error ?? ""),
                    onRetry: () => setState(() => _future = _load()),
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.history_outlined,
                    title: 'No inspections yet',
                    message: 'Completed inspections will appear here.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return _Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text(
                          (item['beat_name'] ??
                                  item['sector_beat_name'] ??
                                  item['status'] ??
                                  'Inspection')
                              .toString(),
                        ),
                        subtitle: Text(
                          (item['completed_at'] ??
                                  item['started_at'] ??
                                  item['created_at'] ??
                                  '')
                              .toString(),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterList extends StatefulWidget {
  final SectorBeat beat;
  final String type;
  final BeatLookups? lookups;

  const _MasterList({
    required this.beat,
    required this.type,
    required this.lookups,
  });

  @override
  State<_MasterList> createState() => _MasterListState();
}

class _MasterListState extends State<_MasterList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await _token();
    return ApiService.getBeatMasters(token, widget.beat.id, widget.type);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingState(label: 'Loading master data...');
            }
            if (snapshot.hasError) {
              return _ErrorState(
                message: userFriendlyErrorMessage(snapshot.error ?? ""),
                onRetry: _reload,
              );
            }
            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return const _EmptyState(
                icon: Icons.dataset_outlined,
                title: 'No records',
                message: 'Records added from web or mobile will appear here.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  return _Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_recordTitle(item, widget.type)),
                      subtitle: Text(_recordSubtitle(item)),
                      trailing: widget.beat.capabilities.canManageMaster
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _openForm(item);
                                if (value == 'delete') _delete(item);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Edit')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
            );
          },
        ),
        if (widget.beat.capabilities.canManageMaster)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () => _openForm(null),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
      ],
    );
  }

  Future<void> _openForm(Map<String, dynamic>? item) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MasterForm(
        type: widget.type,
        initial: item,
        lookups: widget.lookups,
      ),
    );
    if (result == null) return;
    try {
      final token = await _token();
      if (item == null) {
        await ApiService.createBeatMaster(
          token,
          widget.beat.id,
          widget.type,
          result,
        );
      } else {
        await ApiService.updateBeatMaster(
          token,
          widget.beat.id,
          widget.type,
          _asInt(item['id'])!,
          result,
        );
      }
      _reload();
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await _confirm('Delete Record', 'Delete this master record?');
    if (ok != true) return;
    try {
      final token = await _token();
      await ApiService.deleteBeatMaster(
        token,
        widget.beat.id,
        widget.type,
        _asInt(item['id'])!,
      );
      _reload();
    } catch (e) {
      if (mounted) _snack(userFriendlyErrorMessage(e), true);
    }
  }
}

class _MasterForm extends StatefulWidget {
  final String type;
  final Map<String, dynamic>? initial;
  final BeatLookups? lookups;

  const _MasterForm({required this.type, this.initial, this.lookups});

  @override
  State<_MasterForm> createState() => _MasterFormState();
}

class _MasterFormState extends State<_MasterForm> {
  final Map<String, TextEditingController> _controllers = {};
  final List<_VillageContactControllers> _villageContacts = [];
  Map<String, dynamic>? _lookupValue;

  bool get _isVillage => widget.type == 'villages';

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field] = TextEditingController(
        text: widget.initial?[field]?.toString() ?? '',
      );
    }
    if (_lookupKey != null) {
      _lookupValue = _lookupById(_lookupItems, widget.initial?[_lookupKey]);
    }
    if (_isVillage) {
      _loadInitialVillageContacts();
    }
  }

  void _loadInitialVillageContacts() {
    final rawContacts = widget.initial?['contacts'];
    if (rawContacts is List && rawContacts.isNotEmpty) {
      for (final item in rawContacts.whereType<Map>()) {
        _villageContacts.add(
          _VillageContactControllers(
            name: (item['name'] ?? item['contact_person'] ?? '').toString(),
            mobile: (item['mobile'] ?? '').toString(),
          ),
        );
      }
    }
    if (_villageContacts.isEmpty) {
      _villageContacts.add(
        _VillageContactControllers(
          name: widget.initial?['contact_person']?.toString() ?? '',
          mobile: widget.initial?['mobile']?.toString() ?? '',
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final contact in _villageContacts) {
      contact.dispose();
    }
    super.dispose();
  }

  List<String> get _fields {
    switch (widget.type) {
      case 'villages':
        return ['name', 'distance', 'population'];
      case 'assets':
        return ['km_location', 'station', 'description'];
      case 'contacts':
        return ['name', 'incharge', 'mobile'];
      default:
        return ['station', 'km_from', 'km_to', 'time_range'];
    }
  }

  String? get _lookupKey {
    switch (widget.type) {
      case 'assets':
        return 'asset_type_id';
      case 'contacts':
        return 'contact_type_id';
      case 'vulnerable-spots':
        return 'vulnerable_type_id';
    }
    return null;
  }

  List<Map<String, dynamic>> get _lookupItems {
    switch (widget.type) {
      case 'assets':
        return widget.lookups?.assetTypes ?? const [];
      case 'contacts':
        return widget.lookups?.contactTypes ?? const [];
      case 'vulnerable-spots':
        return widget.lookups?.vulnerableTypes ?? const [];
    }
    return const [];
  }

  Map<String, dynamic>? _lookupById(
    List<Map<String, dynamic>> items,
    dynamic id,
  ) {
    final value = _asInt(id);
    if (value == null) return null;
    for (final item in items) {
      if (_asInt(item['id']) == value) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1B2F) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF101828);
    return Material(
      color: bg,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? 'Add Record' : 'Edit Record',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              if (_lookupKey != null) ...[
                _LookupDropdown(
                  label: _lookupKey!.replaceAll('_', ' '),
                  value: _lookupValue,
                  items: _lookupItems,
                  onChanged: (v) => setState(() => _lookupValue = v),
                ),
                const SizedBox(height: 10),
              ],
              ..._fields.map(
                (field) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[field],
                    style: TextStyle(color: titleColor),
                    keyboardType:
                        field.contains('mobile') || field.contains('population')
                            ? TextInputType.number
                            : TextInputType.text,
                    decoration: _themedInput(
                      context,
                      field.replaceAll('_', ' '),
                    ),
                  ),
                ),
              ),
              if (_isVillage) _buildVillageContacts(context),
              const SizedBox(height: 4),
              _FullButton(
                icon: Icons.save_outlined,
                label: 'Save',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVillageContacts(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF101828);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          'Village Contacts',
          style: TextStyle(color: titleColor, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._villageContacts.asMap().entries.map((entry) {
          final index = entry.key;
          final contact = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white12 : _border),
            ),
            child: Column(
              children: [
                TextField(
                  controller: contact.name,
                  style: TextStyle(color: titleColor),
                  decoration: _themedInput(context, 'contact person'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: contact.mobile,
                        style: TextStyle(color: titleColor),
                        keyboardType: TextInputType.phone,
                        decoration: _themedInput(context, 'mobile'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _villageContacts.length == 1
                          ? null
                          : () {
                              setState(() {
                                _villageContacts.removeAt(index).dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                      color: _red,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _villageContacts.add(_VillageContactControllers());
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Contact'),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  void _save() {
    final body = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) body[entry.key] = value;
    }
    if (_isVillage) {
      final contacts = _villageContacts
          .map((contact) => {
                'name': contact.name.text.trim(),
                'mobile': contact.mobile.text.trim(),
              })
          .where((contact) =>
              contact['name']!.toString().isNotEmpty ||
              contact['mobile']!.toString().isNotEmpty)
          .toList();
      if (contacts.isNotEmpty) {
        body['contact_person'] = contacts.map((e) => e['name']).join(', ');
        body['mobile'] = contacts.map((e) => e['mobile']).join(', ');
        body['contacts'] = contacts;
      }
    }
    if (_lookupKey != null) {
      final id = _lookupValue?['id'] ?? widget.initial?[_lookupKey];
      if (id != null) body[_lookupKey!] = id;
    }
    if (widget.type == 'villages' && (body['name'] ?? '').toString().isEmpty) {
      _snack('Name is required.', true);
      return;
    }
    if (widget.type == 'contacts' && (body['name'] ?? '').toString().isEmpty) {
      _snack('Name is required.', true);
      return;
    }
    if (_lookupKey != null && body[_lookupKey!] == null) {
      _snack('Select required lookup.', true);
      return;
    }
    Navigator.pop(context, body);
  }
}

class _VillageContactControllers {
  final TextEditingController name;
  final TextEditingController mobile;

  _VillageContactControllers({String name = '', String mobile = ''})
      : name = TextEditingController(text: name),
        mobile = TextEditingController(text: mobile);

  void dispose() {
    name.dispose();
    mobile.dispose();
  }
}

class _PolylinePreview extends StatelessWidget {
  final List<BeatPoint> points;
  final MapController? controller;

  const _PolylinePreview({required this.points, this.controller});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyState(
        icon: Icons.map_outlined,
        title: 'No route points',
        message: 'Start recording or add a point to preview the polyline.',
      );
    }
    final latLng = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    return SizedBox(
      height: 300,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: latLng.last,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'in.rpfjbp.trinetra',
          ),
          PolylineLayer(
            polylines: [
              Polyline(points: latLng, color: _indigo, strokeWidth: 5),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: latLng.first,
                width: 36,
                height: 36,
                child: const Icon(Icons.flag_circle, color: _green),
              ),
              Marker(
                point: latLng.last,
                width: 36,
                height: 36,
                child: const Icon(Icons.location_on, color: _red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BeatCard extends StatelessWidget {
  final SectorBeat beat;
  final String mode;
  final VoidCallback onTap;

  const _BeatCard(
      {required this.beat, required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF101828);
    final subtitleColor = isDark ? Colors.white70 : _textSec;
    final borderColor = isDark ? Colors.white12 : _border;
    final accent = mode == 'inspect'
        ? _green
        : mode == 'map'
            ? _orange
            : _indigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14233B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.route_outlined, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          beat.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (beat.code.isNotEmpty) beat.code,
                            if (beat.sector.isNotEmpty) beat.sector,
                            if (beat.post.isNotEmpty) beat.post,
                          ].join(' | '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: beat.assignmentType.isEmpty
                        ? 'Assigned'
                        : beat.assignmentType,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniInfo(
                    'Map',
                    beat.mappingState.isEmpty ? '-' : beat.mappingState,
                  ),
                  ...beat.masterCounts.entries.map(
                    (e) => _MiniInfo(e.key, e.value.toString()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  final BeatSectorHomeCard card;
  final VoidCallback onTap;

  const _HomeActionCard({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(card.key), color: _indigo, size: 30),
            const Spacer(),
            Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (card.subtitle?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                card.subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _textSec, fontSize: 12),
              ),
            ],
            if (card.count != null) ...[
              const SizedBox(height: 8),
              _Badge(label: card.count.toString()),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;

  const _Header({required this.title, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        12,
        18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navy, Color(0xFF243660)]),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const _Card({required this.child, this.margin});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2B4A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : _border),
      ),
      child: child,
    );
  }
}

class _FullButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _FullButton({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _indigo.withValues(alpha: 0.45),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? _red : _indigo,
        side: BorderSide(color: danger ? _red : _indigo),
      ),
    );
  }
}

class _LookupDropdown extends StatelessWidget {
  final String label;
  final Map<String, dynamic>? value;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const _LookupDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: value,
      isExpanded: true,
      decoration: _themedInput(context, label),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                  (item['name'] ?? item['title'] ?? item['label'] ?? item['id'])
                      .toString()),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _indigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _indigo,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;

  const _MiniInfo(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.07) : _bgLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : _border),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: isDark ? Colors.white70 : const Color(0xFF344054),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final String text;

  const _Notice({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _LoadingState extends StatelessWidget {
  final String label;

  const _LoadingState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: _textSec)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: _textSec),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textSec)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _red, size: 44),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatDetailData {
  final SectorBeat beat;
  final BeatMapping? mapping;

  const _BeatDetailData(this.beat, this.mapping);
}

InputDecoration _themedInput(BuildContext context, String label) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final labelColor = isDark ? Colors.white70 : _textSec;
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: labelColor),
    hintStyle: TextStyle(color: labelColor),
    filled: true,
    fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : _bgLight,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: isDark ? Colors.white12 : _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _indigo, width: 1.5),
    ),
  );
}

IconData _iconFor(String key) {
  final lower = key.toLowerCase();
  if (lower.contains('map')) return Icons.map_outlined;
  if (lower.contains('master')) return Icons.dataset_outlined;
  if (lower.contains('inspection')) return Icons.fact_check_outlined;
  if (lower.contains('history')) return Icons.history_outlined;
  return Icons.route_outlined;
}

String _recordTitle(Map<String, dynamic> item, String type) {
  return (item['name'] ??
          item['description'] ??
          item['station'] ??
          item['asset_type_name'] ??
          item['contact_type_name'] ??
          item['vulnerable_type_name'] ??
          type)
      .toString();
}

String _recordSubtitle(Map<String, dynamic> item) {
  final values = [
    item['mobile'],
    item['km_location'],
    item['km_from'],
    item['km_to'],
    item['contact_person'],
    item['incharge'],
    item['time_range'],
  ].where((value) => value != null && value.toString().trim().isNotEmpty);
  return values.join(' | ');
}

Future<String> _token() async {
  final token = await Storage.getToken();
  if (token == null || token.isEmpty) {
    throw const SessionExpiredException();
  }
  return token;
}

Future<bool> _ensureLocationReady() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
    return false;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Future<Position> _currentPosition() async {
  final ok = await _ensureLocationReady();
  if (!ok) throw Exception('Location permission is required.');
  return LocationSampler.getBestEffortPosition(
    perSampleTimeout: const Duration(seconds: 20),
  );
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Future<bool?> _confirm(String title, String message) {
  final context = SessionManagerContext.context;
  if (context == null) return Future.value(false);
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK')),
      ],
    ),
  );
}

void _snack(String message, bool isError) {
  final context = SessionManagerContext.context;
  if (context == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? _red : _green,
    ),
  );
}

class SessionManagerContext {
  static BuildContext? get context {
    return SessionManager.navigatorKey.currentContext;
  }
}
