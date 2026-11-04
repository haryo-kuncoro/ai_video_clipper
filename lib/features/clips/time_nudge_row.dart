import 'package:flutter/material.dart';

import 'clip_range.dart';

/// Baris tombol geser waktu (±0,2 / ±1 / ±5 detik) beserta nilai saat ini.
class TimeNudgeRow extends StatelessWidget {
  const TimeNudgeRow({
    super.key,
    required this.label,
    required this.valueMs,
    required this.onNudge,
    this.enabled = true,
  });

  final String label;
  final int valueMs;
  final void Function(int deltaMs) onNudge;
  final bool enabled;

  static const _steps = [-5000, -1000, -200, 200, 1000, 5000];

  static String stepLabel(int d) {
    final abs = d.abs();
    final body = abs >= 1000 ? '${abs ~/ 1000}' : '0.${abs ~/ 100}';
    return '${d > 0 ? '+' : '-'}${body}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${formatPreciseMs(valueMs)}',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final d in _steps)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(52, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: enabled ? () => onNudge(d) : null,
                child: Text(stepLabel(d)),
              ),
          ],
        ),
      ],
    );
  }
}
