import 'package:flutter/material.dart';

/// One panel in a [ReviewComparisonLayout].
///
/// A panel carries a stable [id] (used for keys), a human-readable [label]
/// (used by the compact switcher), and the [child] to display. The layout never
/// inspects or rewrites [child]; the same widget instance is presented in both
/// the side-by-side and focused arrangements.
class ReviewComparisonPanel {
  const ReviewComparisonPanel({
    required this.id,
    required this.label,
    required this.child,
  });

  final String id;
  final String label;
  final Widget child;
}

/// Pure responsive layout primitive for comparing several panels.
///
/// This widget contains no business logic: it only decides between a
/// side-by-side [Row] of all panels (wide viewports) and a focused
/// switcher + single active panel (compact viewports, or an explicit focus
/// toggle on wide viewports). It reads no runtime, holds no domain state beyond
/// the local focus override, and applies no theming of its own.
class ReviewComparisonLayout extends StatefulWidget {
  const ReviewComparisonLayout({
    super.key,
    required this.panels,
    required this.activeIndex,
    required this.onActiveIndexChanged,
    this.breakpoint = 900,
    this.allowModeToggle = false,
  });

  final List<ReviewComparisonPanel> panels;
  final int activeIndex;
  final ValueChanged<int> onActiveIndexChanged;
  final double breakpoint;
  final bool allowModeToggle;

  static const Key switcherKey = Key('review-comparison-switcher');
  static const Key modeToggleKey = Key('review-comparison-mode-toggle');
  static Key panelKey(String id) => Key('review-comparison-panel-$id');

  @override
  State<ReviewComparisonLayout> createState() => _ReviewComparisonLayoutState();
}

class _ReviewComparisonLayoutState extends State<ReviewComparisonLayout> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.panels.isEmpty) {
          return const SizedBox.shrink();
        }

        final wide = constraints.maxWidth >= widget.breakpoint;
        final focused = !wide || _focused;

        final maxIndex = widget.panels.length - 1;
        final activeIndex =
            widget.activeIndex.clamp(0, maxIndex).toInt();
        final activePanel = widget.panels[activeIndex];

        final modeToggle = wide && widget.allowModeToggle
            ? Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ReviewComparisonLayout.modeToggleKey,
                  onPressed: () => setState(() => _focused = !_focused),
                  icon: Icon(
                    focused
                        ? Icons.view_column_outlined
                        : Icons.crop_free_outlined,
                  ),
                  label: Text(focused ? 'Compare all' : 'Focus'),
                ),
              )
            : null;

        if (!focused) {
          final row = Row(
            children: [
              for (final panel in widget.panels)
                Expanded(
                  child: KeyedSubtree(
                    key: ReviewComparisonLayout.panelKey(panel.id),
                    child: panel.child,
                  ),
                ),
            ],
          );
          if (modeToggle == null) {
            return row;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              modeToggle,
              Expanded(child: row),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              key: ReviewComparisonLayout.switcherKey,
              segments: [
                for (var i = 0; i < widget.panels.length; i++)
                  ButtonSegment<int>(
                    value: i,
                    label: Text(
                      widget.panels[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {activeIndex},
              onSelectionChanged: (selection) =>
                  widget.onActiveIndexChanged(selection.first),
            ),
            if (modeToggle != null) modeToggle,
            Expanded(
              child: KeyedSubtree(
                key: ReviewComparisonLayout.panelKey(activePanel.id),
                child: activePanel.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
