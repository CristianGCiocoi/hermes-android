import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gateway_insight.dart';
import '../services/gateway_activity_center_controller.dart';

class GatewayActivityCenterSheet extends StatelessWidget {
  final GatewayActivityCenterController controller;

  const GatewayActivityCenterSheet({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, scrollController) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final hasContent =
              controller.legacyTransportFallback ||
              controller.needsInput ||
              controller.turnStatus != null ||
              controller.notifications.isNotEmpty ||
              controller.tools.isNotEmpty ||
              controller.subagents.isNotEmpty ||
              controller.notices.isNotEmpty;
          return SafeArea(
            top: false,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hermes activity',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                _summary(controller),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close activity',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!hasContent)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No activity yet')),
                  )
                else ...[
                  if (controller.legacyTransportFallback)
                    SliverToBoxAdapter(
                      child: _StatusTile(
                        key: const Key('activity-legacy-status'),
                        icon: Icons.cloud_off_outlined,
                        title: 'Legacy transport',
                        detail:
                            'Background recovery is unavailable for this Gateway.',
                        color: Colors.orange,
                      ),
                    ),
                  if (controller.needsInput)
                    const SliverToBoxAdapter(
                      child: _StatusTile(
                        key: Key('activity-needs-input'),
                        icon: Icons.help_outline,
                        title: 'Needs input',
                        detail: 'Hermes is waiting for your response.',
                      ),
                    ),
                  if (controller.turnStatus case final status?)
                    SliverToBoxAdapter(
                      child: _StatusTile(
                        icon: Icons.sync,
                        title: 'Current status',
                        detail: status.text,
                      ),
                    ),
                  if (controller.notifications.isNotEmpty)
                    _section(
                      context,
                      'Notices',
                      controller.notifications.map(
                        (notice) => ListTile(
                          leading: Icon(_notificationIcon(notice.level)),
                          title: Text(notice.text),
                          trailing: IconButton(
                            tooltip: 'Dismiss notice',
                            onPressed: () =>
                                controller.clearNotification(notice.key),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ),
                  if (controller.tools.isNotEmpty)
                    _section(
                      context,
                      'Tools',
                      controller.tools.map(
                        (activity) => ListTile(
                          leading: activity.isTerminal
                              ? Icon(
                                  activity.isFailed
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                )
                              : const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                          title: Text(activity.displayName),
                          subtitle: Text(
                            [
                              activity.statusLabel,
                              if (activity.detail != null) activity.detail!,
                            ].join(' • '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  if (controller.subagents.isNotEmpty)
                    _section(
                      context,
                      'Delegated tasks',
                      controller.subagents.map(
                        (activity) => ListTile(
                          leading: activity.isComplete
                              ? const Icon(Icons.check_circle_outline)
                              : const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                          title: Text(activity.goal),
                          subtitle: Text(
                            [
                              activity.phase.name,
                              if (activity.detail != null) activity.detail!,
                            ].join(' • '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  if (controller.notices.isNotEmpty)
                    _section(
                      context,
                      'Reviews and completed work',
                      controller.notices.map(
                        (entry) => ListTile(
                          key: ValueKey(
                            'activity-notice-${entry.notice.identity}',
                          ),
                          leading: Icon(
                            entry.notice.kind == GatewayNoticeKind.review
                                ? Icons.fact_check_outlined
                                : Icons.task_alt_outlined,
                          ),
                          title: Text(entry.notice.title),
                          subtitle: Text(
                            entry.notice.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: entry.dismissed
                              ? const Tooltip(
                                  message: 'Dismissed from transcript',
                                  child: Icon(Icons.visibility_off_outlined),
                                )
                              : null,
                          onTap: () => _showNotice(context, entry.notice),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _summary(GatewayActivityCenterController controller) {
    if (controller.needsInput) return 'Needs your input';
    if (controller.runningCount > 0) {
      return '${controller.runningCount} running';
    }
    final completed = controller.tools.length + controller.subagents.length;
    return completed == 0
        ? 'Session status and history'
        : '$completed recorded';
  }

  static SliverMainAxisGroup _section(
    BuildContext context,
    String title,
    Iterable<Widget> children,
  ) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        SliverList.list(children: children.toList(growable: false)),
      ],
    );
  }

  static IconData _notificationIcon(GatewayNotificationLevel level) =>
      switch (level) {
        GatewayNotificationLevel.info => Icons.info_outline,
        GatewayNotificationLevel.success => Icons.check_circle_outline,
        GatewayNotificationLevel.warning => Icons.warning_amber_outlined,
        GatewayNotificationLevel.error => Icons.error_outline,
      };

  static Future<void> _showNotice(BuildContext context, GatewayNotice notice) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notice.title),
        content: SingleChildScrollView(
          child: SelectionArea(child: Text(notice.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color? color;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.detail,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }
}
