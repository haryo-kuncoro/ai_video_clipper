import 'package:flutter/material.dart';

import '../../services/subtitle/subtitle_style.dart';

/// Kontrol gaya subtitle yang dipakai bersama (kartu uji subtitle dan
/// editor clip). Tidak menyimpan state: semua perubahan lewat [onChanged].
class SubtitleStyleControls extends StatelessWidget {
  const SubtitleStyleControls({
    super.key,
    required this.style,
    required this.onChanged,
    this.enabled = true,
  });

  final SubtitleStyle style;
  final ValueChanged<SubtitleStyle> onChanged;
  final bool enabled;

  void _edit(SubtitleStyle Function(SubtitleStyle) change) {
    onChanged(change(style).copyWith(preset: SubtitlePreset.custom));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = style;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final preset in SubtitlePresets.selectable)
              ChoiceChip(
                label: Text(preset.label),
                selected: s.preset == preset,
                onSelected:
                    enabled ? (_) => onChanged(SubtitlePresets.style(preset)) : null,
              ),
            if (s.preset == SubtitlePreset.custom)
              const ChoiceChip(label: Text('Custom'), selected: true),
          ],
        ),
        const SizedBox(height: 12),
        Text('Posisi', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<SubtitlePosition>(
          segments: [
            for (final pos in SubtitlePosition.values)
              ButtonSegment(value: pos, label: Text(pos.label)),
          ],
          selected: {s.position},
          onSelectionChanged:
              enabled ? (v) => _edit((x) => x.copyWith(position: v.first)) : null,
        ),
        _slider(
          context,
          'Ukuran font ${s.fontSize}',
          s.fontSize.toDouble(),
          30,
          100,
          (v) => _edit((x) => x.copyWith(fontSize: v.round())),
        ),
        _slider(
          context,
          'Maks. karakter per baris ${s.maxCharsPerLine}',
          s.maxCharsPerLine.toDouble(),
          12,
          40,
          (v) => _edit((x) => x.copyWith(maxCharsPerLine: v.round())),
        ),
        _slider(
          context,
          'Outline ${s.outlineWidth.toStringAsFixed(1)}',
          s.outlineWidth,
          0,
          10,
          (v) => _edit((x) => x.copyWith(outlineWidth: v)),
        ),
        Row(
          children: [
            const Text('Font'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: s.fontFamily,
              items: [
                for (final f in subtitleFontFamilies)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: enabled
                  ? (v) {
                      if (v != null) _edit((x) => x.copyWith(fontFamily: v));
                    }
                  : null,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('Tebal'),
              selected: s.bold,
              onSelected:
                  enabled ? (v) => _edit((x) => x.copyWith(bold: v)) : null,
            ),
            FilterChip(
              label: const Text('HURUF KAPITAL'),
              selected: s.uppercase,
              onSelected:
                  enabled ? (v) => _edit((x) => x.copyWith(uppercase: v)) : null,
            ),
            FilterChip(
              label: const Text('Bayangan'),
              selected: s.shadow,
              onSelected:
                  enabled ? (v) => _edit((x) => x.copyWith(shadow: v)) : null,
            ),
            FilterChip(
              label: const Text('Kotak latar'),
              selected: s.background,
              onSelected:
                  enabled ? (v) => _edit((x) => x.copyWith(background: v)) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _slider(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
