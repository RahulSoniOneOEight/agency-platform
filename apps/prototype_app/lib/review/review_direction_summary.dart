import 'package:flutter/material.dart';

import '../direction/prototype_direction.dart';
import '../registry/prototype_registry.dart';

/// Neutral metadata card for a single runtime [PrototypeDirection].
///
/// Every displayed value is read from [direction]; no direction metadata is
/// hard-coded here. The card is deliberately non-evaluative: it never ranks,
/// scores, or recommends a direction. An explicit [onSelect] action is exposed
/// only when the caller supplies one, so selection stays a separate decision.
class ReviewDirectionSummary extends StatelessWidget {
  const ReviewDirectionSummary({
    super.key,
    required this.direction,
    this.selected = false,
    this.onSelect,
  });

  final PrototypeDirection direction;
  final bool selected;
  final VoidCallback? onSelect;

  static Key cardKey(String directionId) =>
      Key('review-direction-summary-$directionId');

  static Key selectButtonKey(String directionId) =>
      Key('review-direction-select-$directionId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey(direction.id),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  direction.id.toUpperCase(),
                  style: theme.textTheme.titleMedium,
                ),
                Text(direction.name, style: theme.textTheme.titleMedium),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Selected',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(direction.strategicGoal, style: theme.textTheme.bodyMedium),
            const Divider(height: 24),
            _definition(context, 'Primary journey', direction.primaryJourney),
            _definition(context, 'Discovery', direction.discoveryModel),
            _definition(
              context,
              'Merchandising',
              direction.merchandisingModel,
            ),
            _definition(context, 'Transaction', direction.transactionModel),
            _definition(context, 'Density', direction.canonicalDensity),
            const SizedBox(height: 16),
            Text('Governed patterns', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final patternId in direction.patterns)
                  _chip(context, PrototypeRegistry.labelFor(patternId)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Components', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final componentId in direction.components)
                  _chip(context, componentId),
              ],
            ),
            if (onSelect != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Select this direction: ${direction.name}',
                  child: FilledButton(
                    key: selectButtonKey(direction.id),
                    onPressed: onSelect,
                    child: const Text('Select this direction'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _definition(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
