import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/storage.dart';
import 'duty_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<_HistoryViewData> _historyFuture;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _historyFuture = _loadHistory();
  }

  Future<_HistoryViewData> _loadHistory() async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      return _HistoryViewData.empty(_formatApiDate(_selectedDate));
    }

    final payload = await ApiService.getHomeDutyReport(
      token,
      date: _formatApiDate(_selectedDate),
    );
    final items = (payload['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();

    return _HistoryViewData(
      date: payload['date']?.toString() ?? _formatApiDate(_selectedDate),
      totalDuties: (payload['total_dutys'] as num?)?.toInt() ?? items.length,
      items: items,
    );
  }

  void _refresh() {
    setState(() {
      _historyFuture = _loadHistory();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _historyFuture = _loadHistory();
    });
  }

  String _formatDisplayDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }

  String _formatApiDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duty History'),
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
      body: FutureBuilder<_HistoryViewData>(
        future: _historyFuture,
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

          final viewData = snapshot.data ??
              _HistoryViewData.empty(_formatApiDate(_selectedDate));
          final summary = _HistorySummary.fromItems(
            totalDuties: viewData.totalDuties,
            items: viewData.items,
          );

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _buildFilterCard(isDark, viewData),
                const SizedBox(height: 14),
                _buildSummaryRow(isDark, summary),
                const SizedBox(height: 16),
                Text(
                  'Duty Report',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${viewData.items.length} records found for ${_formatDisplayDate(_selectedDate)}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                if (viewData.items.isEmpty)
                  _buildEmptyState(isDark)
                else
                  ...viewData.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryDutyCard(
                        item: item,
                        isDark: isDark,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterCard(bool isDark, _HistoryViewData viewData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected Date',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_rounded,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDisplayDate(_selectedDate),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(bool isDark, _HistorySummary summary) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            isDark: isDark,
            title: 'Total',
            value: summary.total.toString(),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            isDark: isDark,
            title: 'Completed',
            value: summary.completed.toString(),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            isDark: isDark,
            title: 'Pending',
            value: summary.pending.toString(),
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required bool isDark,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'No records for this date.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
    );
  }
}

class _HistoryDutyCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isDark;

  const _HistoryDutyCard({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final deploymentId = (item['deployment_id'] as num?)?.toInt();
    final stage = _HistoryStage.fromApiItem(item);
    final activityCount = (item['activity_count'] as num?)?.toInt() ?? 0;
    final postName = item['post_name']?.toString().trim();
    final beatName = item['beat_name']?.toString().trim();
    final shiftName = item['shift_name']?.toString().trim();
    final locationLine = [
      if (postName != null && postName.isNotEmpty) postName,
      if (shiftName != null && shiftName.isNotEmpty) shiftName,
    ];

    return InkWell(
      onTap: () {
        if (deploymentId == null) {
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DutyDetailScreen(deploymentId: deploymentId),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        beatName != null && beatName.isNotEmpty
                            ? beatName
                            : 'Unnamed Beat',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locationLine.isEmpty
                            ? 'Post / shift not available'
                            : locationLine.join(' | '),
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: stage.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      color: stage.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _infoChip(
                  icon: Icons.calendar_today_rounded,
                  label: item['duty_date']?.toString() ?? '-',
                ),
                _infoChip(
                  icon: Icons.route_rounded,
                  label: '$activityCount activities',
                ),
                if (deploymentId != null)
                  _infoChip(
                    icon: Icons.badge_outlined,
                    label: 'ID $deploymentId',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.reportLine,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (stage.endedStage.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ended stage: ${stage.endedStage}',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _LogTimeline(
              isDark: isDark,
              log: item['log'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTimeline extends StatelessWidget {
  final bool isDark;
  final dynamic log;

  const _LogTimeline({
    required this.isDark,
    required this.log,
  });

  @override
  Widget build(BuildContext context) {
    final logMap = log is Map ? log.cast<String, dynamic>() : const <String, dynamic>{};
    final steps = [
      _TimelineStep('Login', _readTime(logMap['login_time'])),
      _TimelineStep('Start', _readTime(logMap['duty_start_time'])),
      _TimelineStep('End', _readTime(logMap['duty_end_time'])),
      _TimelineStep('Logout', _readTime(logMap['logout_time'])),
    ];

    return Column(
      children: steps
          .map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: step.value == '-' ? Colors.grey : Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    step.value,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  static String _readTime(dynamic raw) {
    final value = raw?.toString();
    if (value == null || value.trim().isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }

    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _TimelineStep {
  final String label;
  final String value;

  const _TimelineStep(this.label, this.value);
}

class _HistorySummary {
  final int total;
  final int completed;
  final int pending;

  const _HistorySummary({
    required this.total,
    required this.completed,
    required this.pending,
  });

  factory _HistorySummary.fromItems({
    required int totalDuties,
    required List<Map<String, dynamic>> items,
  }) {
    var completed = 0;

    for (final item in items) {
      final status = (item['status'] as num?)?.toInt() ?? 0;
      if (status >= 4) {
        completed++;
      }
    }

    return _HistorySummary(
      total: totalDuties,
      completed: completed,
      pending: (totalDuties - completed).clamp(0, totalDuties).toInt(),
    );
  }
}

class _HistoryStage {
  final String label;
  final String endedStage;
  final String reportLine;
  final Color color;

  const _HistoryStage({
    required this.label,
    required this.endedStage,
    required this.reportLine,
    required this.color,
  });

  factory _HistoryStage.fromApiItem(Map<String, dynamic> item) {
    final status = (item['status'] as num?)?.toInt() ?? 0;
    final statusLabel = item['status_label']?.toString().trim();
    final endedStage = item['ended_stage']?.toString().trim() ?? '';

    switch (status) {
      case 4:
        return _HistoryStage(
          label: statusLabel?.isNotEmpty == true ? statusLabel! : 'Completed',
          endedStage: endedStage,
          reportLine: 'Duty completed.',
          color: Colors.green,
        );
      case 3:
        return _HistoryStage(
          label: statusLabel?.isNotEmpty == true ? statusLabel! : 'Logout Pending',
          endedStage: endedStage,
          reportLine: 'Duty ended — logout pending.',
          color: Colors.deepPurple,
        );
      case 2:
        return _HistoryStage(
          label: statusLabel?.isNotEmpty == true ? statusLabel! : 'Dismount Pending',
          endedStage: endedStage,
          reportLine: 'Duty active — dismount pending.',
          color: Colors.blue,
        );
      case 1:
        return _HistoryStage(
          label: statusLabel?.isNotEmpty == true ? statusLabel! : 'Mount Pending',
          endedStage: endedStage,
          reportLine: 'Logged in — mount pending.',
          color: Colors.orange,
        );
      default:
        return _HistoryStage(
          label: statusLabel?.isNotEmpty == true ? statusLabel! : 'Pending',
          endedStage: endedStage,
          reportLine: 'Duty not yet started.',
          color: Colors.redAccent,
        );
    }
  }
}

class _HistoryViewData {
  final String date;
  final int totalDuties;
  final List<Map<String, dynamic>> items;

  const _HistoryViewData({
    required this.date,
    required this.totalDuties,
    required this.items,
  });

  factory _HistoryViewData.empty(String date) {
    return _HistoryViewData(
      date: date,
      totalDuties: 0,
      items: const [],
    );
  }
}
