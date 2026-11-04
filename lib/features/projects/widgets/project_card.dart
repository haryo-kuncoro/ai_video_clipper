import 'package:flutter/material.dart';

import '../../../core/utils/format_utils.dart';
import '../../../database/models/project_summary.dart';
import '../project_status_label.dart';

enum _CardAction { rename, delete }

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.summary,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ProjectSummary summary;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = summary.project;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text('${summary.clipCount} clips',
                        style: theme.textTheme.bodyMedium),
                    Text(formatSourceDuration(summary.sourceDurationMs),
                        style: theme.textTheme.bodyMedium),
                    Text(formatRelativeDate(project.updatedAt),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(projectStatusLabel(project.status)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CardAction>(
                tooltip: 'Menu project',
                onSelected: (action) {
                  switch (action) {
                    case _CardAction.rename:
                      onRename();
                    case _CardAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _CardAction.rename,
                    child: Text('Ganti nama'),
                  ),
                  PopupMenuItem(
                    value: _CardAction.delete,
                    child: Text('Hapus'),
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
