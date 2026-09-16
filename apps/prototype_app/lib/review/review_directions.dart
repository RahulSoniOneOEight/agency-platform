import 'package:flutter/material.dart';

import '../direction/prototype_direction.dart';
import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';

/// Direction browsing plus the explicit overall-direction selection action.
///
/// The selector only updates a local preview direction; previewing alone never
/// changes `selected_direction`. Review state changes only when the reviewer
/// presses `Select this direction`, and the runtime's declared `default_direction`
/// is used only as the initial local preview, never as a silent client selection.
class ReviewDirections extends StatefulWidget {
  const ReviewDirections({
    super.key,
    required this.runtime,
    required this.controller,
  });

  final PrototypeRuntime runtime;
  final ReviewController controller;

  @override
  State<ReviewDirections> createState() => _ReviewDirectionsState();
}

class _ReviewDirectionsState extends State<ReviewDirections> {
  late String _previewDirectionId;

  @override
  void initState() {
    super.initState();
    _previewDirectionId = widget.runtime.defaultDirection;
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.state.selectedDirection;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Experience directions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Previewing: ${_previewDirectionId.toUpperCase()}'),
            Text('Selected direction: ${selected ?? 'Not selected'}'),
            const SizedBox(height: 12),
            for (final id in runtime.allowedDirections)
              _DirectionOption(
                direction: runtime.directions[id]!,
                previewed: id == _previewDirectionId,
                onSelected: () => setState(() => _previewDirectionId = id),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => controller.selectDirection(_previewDirectionId),
                child: const Text('Select this direction'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DirectionOption extends StatelessWidget {
  const _DirectionOption({
    required this.direction,
    required this.previewed,
    required this.onSelected,
  });

  final PrototypeDirection direction;
  final bool previewed;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: previewed,
      onTap: onSelected,
      leading: Icon(
        previewed ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(direction.name),
      subtitle: Text('${direction.id} · ${direction.strategicGoal}'),
    );
  }
}
