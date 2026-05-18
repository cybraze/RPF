import 'package:flutter/material.dart';

import '../models/inspection_task.dart';
import '../services/api_service.dart';
import '../utils/app_error_message.dart';
import '../utils/storage.dart';

class InspectionTasksScreen extends StatefulWidget {
  const InspectionTasksScreen({super.key});

  @override
  State<InspectionTasksScreen> createState() => _InspectionTasksScreenState();
}

class _InspectionTasksScreenState extends State<InspectionTasksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<InspectionTaskPage> _pendingFuture;
  late Future<InspectionTaskPage> _completeFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pendingFuture = _loadTasks('pending');
    _completeFuture = _loadTasks('complete');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<InspectionTaskPage> _loadTasks(String status) async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      throw const SessionExpiredException();
    }
    return ApiService.getInspectionTasks(token, status: status);
  }

  void _refreshStatus(String status) {
    setState(() {
      if (status == 'pending') {
        _pendingFuture = _loadTasks('pending');
      } else {
        _completeFuture = _loadTasks('complete');
      }
    });
  }

  void _refreshAll() {
    setState(() {
      _pendingFuture = _loadTasks('pending');
      _completeFuture = _loadTasks('complete');
    });
  }

  Future<void> _openDetail(InspectionTask task) async {
    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      _showMessage('Session expired. Please log in.');
      return;
    }

    InspectionTask detail = task;
    try {
      detail = await ApiService.getInspectionTaskDetail(token, task.id);
    } catch (_) {
      detail = task;
    }

    if (!mounted) {
      return;
    }

    final shouldComplete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _TaskDetailSheet(
        task: detail,
        onComplete: detail.isPending
            ? () => Navigator.pop(sheetContext, true)
            : null,
      ),
    );

    if (shouldComplete == true && mounted) {
      _completeTask(detail);
    }
  }

  Future<void> _completeTask(InspectionTask task) async {
    final remark = await showDialog<String>(
      context: context,
      builder: (context) => const _CompleteTaskDialog(),
    );

    if (remark == null || remark.isEmpty) {
      return;
    }

    final token = await Storage.getToken();
    if (token == null || token.isEmpty) {
      _showMessage('Session expired. Please log in.');
      return;
    }

    try {
      await ApiService.completeInspectionTask(
        token,
        task.id,
        completionRemark: remark,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Task completed.');
      _refreshAll();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(userFriendlyErrorMessage(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Task'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      backgroundColor:
          isDark ? const Color(0xFF0B1F3A) : const Color(0xFFF4F6FA),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TaskList(
            future: _pendingFuture,
            status: 'pending',
            onRefresh: () async => _refreshStatus('pending'),
            onTap: _openDetail,
            onComplete: _completeTask,
          ),
          _TaskList(
            future: _completeFuture,
            status: 'complete',
            onRefresh: () async => _refreshStatus('complete'),
            onTap: _openDetail,
            onComplete: _completeTask,
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  final Future<InspectionTaskPage> future;
  final String status;
  final Future<void> Function() onRefresh;
  final ValueChanged<InspectionTask> onTap;
  final ValueChanged<InspectionTask> onComplete;

  const _TaskList({
    required this.future,
    required this.status,
    required this.onRefresh,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<InspectionTaskPage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _TaskMessage(
            title: 'Failed to load tasks',
            message: userFriendlyErrorMessage(snapshot.error!),
            icon: Icons.error_outline_rounded,
          );
        }

        final page = snapshot.data;
        final tasks = page?.tasks ?? const <InspectionTask>[];

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _CountHeader(page: page, isDark: isDark),
              const SizedBox(height: 14),
              if (tasks.isEmpty)
                _TaskMessage(
                  title: status == 'pending'
                      ? 'No pending tasks'
                      : 'No completed tasks',
                  message: '',
                  icon: Icons.task_alt_rounded,
                )
              else
                ...tasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TaskCard(
                      task: task,
                      isDark: isDark,
                      onTap: () => onTap(task),
                      onComplete:
                          task.isPending ? () => onComplete(task) : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CountHeader extends StatelessWidget {
  final InspectionTaskPage? page;
  final bool isDark;

  const _CountHeader({required this.page, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountTile(
            label: 'Pending',
            value: (page?.pendingCount ?? 0).toString(),
            color: Colors.orange,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountTile(
            label: 'Completed',
            value: (page?.completeCount ?? 0).toString(),
            color: Colors.green,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _CountTile({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final InspectionTask task;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  const _TaskCard({
    required this.task,
    required this.isDark,
    required this.onTap,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = task.isPending ? Colors.orange : Colors.green;

    return InkWell(
      onTap: onTap,
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
                  child: Text(
                    task.description.isEmpty
                        ? 'Inspection task #${task.id}'
                        : task.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(
                  label: task.isPending ? 'Pending' : 'Complete',
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.location_on_outlined,
                  label: task.postName ?? 'Post not available',
                  isDark: isDark,
                ),
                if (task.inspectionType != null)
                  _InfoChip(
                    icon: Icons.fact_check_outlined,
                    label: task.inspectionType!,
                    isDark: isDark,
                  ),
                if (task.pendingDays != null)
                  _InfoChip(
                    icon: Icons.schedule_rounded,
                    label: '${task.pendingDays} days pending',
                    isDark: isDark,
                  ),
              ],
            ),
            if (task.photoUrl != null) ...[
              const SizedBox(height: 12),
              _TaskPhoto(url: task.photoUrl!, height: 150),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Assigned by: ${task.assignedByName ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (onComplete != null) ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Complete'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailSheet extends StatelessWidget {
  final InspectionTask task;
  final VoidCallback? onComplete;

  const _TaskDetailSheet({required this.task, this.onComplete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Task Detail',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            task.description.isEmpty ? '-' : task.description,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (task.photoUrl != null)
            _TaskPhoto(url: task.photoUrl!, height: 220),
          const SizedBox(height: 14),
          _DetailRow('Status', task.isPending ? 'Pending' : 'Complete'),
          _DetailRow('Post', task.postName ?? '-'),
          _DetailRow('Inspection type', task.inspectionType ?? '-'),
          _DetailRow('Inspector', _joinName(task.inspectorName, task.inspectorDesignation)),
          _DetailRow('Assigned by', _joinName(task.assignedByName, task.assignedByDesignation)),
          _DetailRow('Created at', task.createdAt ?? '-'),
          _DetailRow('Completed at', task.completedAt ?? '-'),
          if (task.pendingDays != null)
            _DetailRow('Pending days', task.pendingDays.toString()),
          if (task.completionRemark != null)
            _DetailRow('Completion remark', task.completionRemark!),
          if (onComplete != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: onComplete,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Complete with Remark'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _joinName(String? name, String? designation) {
    final parts = [
      if (name != null) name,
      if (designation != null) designation,
    ];
    return parts.isEmpty ? '-' : parts.join(' | ');
  }
}

class _TaskPhoto extends StatelessWidget {
  final String url;
  final double height;

  const _TaskPhoto({
    required this.url,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return Container(
            height: height,
            width: double.infinity,
            color: isDark ? const Color(0xFF111827) : const Color(0xFFF1F5F9),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          height: height,
          width: double.infinity,
          color: isDark ? const Color(0xFF111827) : const Color(0xFFF1F5F9),
          alignment: Alignment.center,
          child: Text(
            'Photo unavailable',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
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
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white70 : Colors.black54),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteTaskDialog extends StatefulWidget {
  const _CompleteTaskDialog();

  @override
  State<_CompleteTaskDialog> createState() => _CompleteTaskDialogState();
}

class _CompleteTaskDialogState extends State<_CompleteTaskDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete Task'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Completion remark',
            hintText: 'Add completion note...',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Remark is required.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Complete'),
        ),
      ],
    );
  }
}

class _TaskMessage extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _TaskMessage({
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF1D4ED8)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
