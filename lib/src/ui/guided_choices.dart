import 'package:flutter/material.dart';

import '../guided.dart';
import 'palette.dart';

/// The buttons of a guided flow, as the chat widget shows them: outlined pills in the brand colour, wrapping onto lines.
class KerabieGuidedChoices extends StatelessWidget {
  const KerabieGuidedChoices({
    super.key,
    required this.choices,
    required this.palette,
    required this.onPick,
    this.disabled = false,
  });

  final List<KerabieGuidedChoice> choices;
  final KerabiePalette palette;
  final ValueChanged<KerabieGuidedChoice> onPick;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in choices)
              Semantics(
                button: true,
                label: c.label,
                child: Opacity(
                  opacity: disabled ? 0.5 : 1,
                  child: Material(
                    color: palette.background,
                    shape: StadiumBorder(side: BorderSide(color: palette.accent, width: 1.5)),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: disabled ? null : () => onPick(c),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text(
                            c.label,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.accent, fontFamily: palette.fontFamily),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
