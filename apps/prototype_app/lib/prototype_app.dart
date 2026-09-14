import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'direction/direction_loader.dart';
import 'screens/prototype_shell.dart';

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key, this.initialDirection = 'a'});

  final String initialDirection;

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late String _directionId;

  @override
  void initState() {
    super.initState();
    _directionId = {'a', 'b', 'c'}.contains(widget.initialDirection) ? widget.initialDirection : 'a';
  }

  @override
  Widget build(BuildContext context) {
    final direction = DirectionLoader.resolve(_directionId);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agency Prototype',
      theme: AgencyTheme.light(),
      home: Scaffold(
        appBar: AppBar(
          title: Text(direction.name),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'a', label: Text('A')),
                    ButtonSegment(value: 'b', label: Text('B')),
                    ButtonSegment(value: 'c', label: Text('C')),
                  ],
                  selected: {_directionId},
                  onSelectionChanged: (selection) => setState(() => _directionId = selection.first),
                  showSelectedIcon: false,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(
                '${direction.strategicGoal} · ${direction.primaryJourney}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(child: PrototypeShell(direction: direction)),
          ],
        ),
      ),
    );
  }
}
