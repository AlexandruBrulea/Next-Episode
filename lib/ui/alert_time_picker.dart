import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AlertTimePicker extends StatefulWidget {
  final int minutes;
  final bool after;
  final void Function(int minutes, bool after) onChanged;
  const AlertTimePicker({super.key, required this.minutes, required this.after, required this.onChanged});
  @override
  State<AlertTimePicker> createState() => _AlertTimePickerState();
}

class _AlertTimePickerState extends State<AlertTimePicker> {
  late int hours = widget.minutes ~/ 60;
  late int minutes = widget.minutes % 60;
  late bool after = widget.after;
  late final hourScroll = FixedExtentScrollController(initialItem: hours);
  late final minuteScroll = FixedExtentScrollController(initialItem: minutes);
  late final directionScroll = FixedExtentScrollController(initialItem: after ? 1 : 0);
  @override
  void dispose() {
    hourScroll.dispose(); minuteScroll.dispose(); directionScroll.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final label = hours == 0 && minutes == 0 ? 'At broadcast time'
        : '${hours > 0 ? '$hours h ' : ''}${minutes > 0 ? '$minutes m ' : ''}${after ? 'after' : 'before'}';
    Widget wheel(String label, FixedExtentScrollController controller, List<String> values, ValueChanged<int> change) =>
      Expanded(child: Semantics(label: label, child: CupertinoPicker(
        scrollController: controller, itemExtent: 44, diameterRatio: 1.3,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: (index) => setState(() => change(index)),
        children: [for (final value in values) Center(child: Text(value,
          style: Theme.of(context).textTheme.titleLarge))],
      )));
    return Card(clipBehavior: Clip.antiAlias, child: ExpansionTile(
      initiallyExpanded: false,
      maintainState: true,
      leading: const Icon(Icons.schedule, size: 22),
      title: const Text('Alert Time'),
      subtitle: Text(label),
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (expanded) {
        if (!expanded) widget.onChanged(hours * 60 + minutes, after);
      },
      children: [
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child:
        NotificationListener<ScrollEndNotification>(onNotification: (_) {
          widget.onChanged(hours * 60 + minutes, after);
          return false;
        }, child: SizedBox(height: 176, child: Stack(alignment: Alignment.center, children: [
          IgnorePointer(child: Container(height: 44, decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(22)))),
          Row(children: [
            wheel('Hours', hourScroll, [for (var i = 0; i < 24; i++) '$i h'], (i) => hours = i),
            wheel('Minutes', minuteScroll, [for (var i = 0; i < 60; i++) '$i m'], (i) => minutes = i),
            wheel('Before or after', directionScroll, ['before', 'after'], (i) => after = i == 1),
          ]),
        ]))),
      ),
    ]));
  }
}
