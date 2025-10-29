// lib/widgets/time_setter.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class TimeSetterCard extends StatefulWidget {
  final TimeOfDay initialTime;
  final String initialTimezone; // IANA
  final int minuteInterval;     // 1..30
  final void Function(TimeOfDay time, String timezone)? onChanged;

  const TimeSetterCard({
    super.key,
    required this.initialTime,
    this.initialTimezone = 'Europe/Chisinau',
    this.minuteInterval = 5,
    this.onChanged,
  });

  @override
  State<TimeSetterCard> createState() => _TimeSetterCardState();
}

class _TimeSetterCardState extends State<TimeSetterCard> {
  late TimeOfDay _time;
  late String _timezone;

  static const _tzOptions = <String>[
    'Europe/Chisinau',
    'Europe/Bucharest',
    'Europe/Kyiv',
    'Europe/London',
    'UTC',
  ];

  @override
  void initState() {
    super.initState();
    _time = widget.initialTime;
    _timezone = widget.initialTimezone;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _openPicker() async {
    final TimeOfDay init = _time;
    TimeOfDay tmp = init;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final color = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.35,
          maxChildSize: 0.7,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: color.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.1), blurRadius: 16)],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: color.outlineVariant, borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Pick a time', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(brightness: Brightness.light),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: true,
                        minuteInterval: widget.minuteInterval.clamp(1, 30),
                        initialDateTime: DateTime(2024, 1, 1, init.hour, init.minute),
                        onDateTimeChanged: (dt) {
                          tmp = TimeOfDay(hour: dt.hour, minute: dt.minute);
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewPaddingOf(ctx).bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _time = tmp);
                              widget.onChanged?.call(_time, _timezone);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyQuick(Duration delta) {
    final base = DateTime(2000, 1, 1, _time.hour, _time.minute);
    final next = base.add(delta);
    setState(() => _time = TimeOfDay(hour: next.hour, minute: next.minute));
    widget.onChanged?.call(_time, _timezone);
  }

  void _preset(int h, int m) {
    setState(() => _time = TimeOfDay(hour: h, minute: m));
    widget.onChanged?.call(_time, _timezone);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.schedule, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Schedule time',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer, borderRadius: BorderRadius.circular(100),
                ),
                child: Text(_timezone, style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Time pill
          InkWell(
            onTap: _openPicker,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(.10), cs.primary.withOpacity(.03)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_filled_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    '${_two(_time.hour)}:${_two(_time.minute)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text('Change', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_up_rounded, color: cs.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Timezone select
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Timezone',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _tzOptions.contains(_timezone) ? _timezone : _tzOptions.first,
                items: _tzOptions.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _timezone = v);
                  widget.onChanged?.call(_time, _timezone);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipBtn(label: 'Now', onTap: () {
                final now = TimeOfDay.now();
                setState(() => _time = TimeOfDay(hour: now.hour, minute: now.minute));
                widget.onChanged?.call(_time, _timezone);
              }),
              _ChipBtn(label: '+30m', onTap: () => _applyQuick(const Duration(minutes: 30))),
              _ChipBtn(label: '+1h', onTap: () => _applyQuick(const Duration(hours: 1))),
              _ChipBtn(label: '09:00', onTap: () => _preset(9, 0)),
              _ChipBtn(label: '14:00', onTap: () => _preset(14, 0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChipBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
