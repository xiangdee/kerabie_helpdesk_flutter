import 'package:flutter/material.dart';

import 'palette.dart';

enum KerabieTab { home, chat, help, tickets }

/// The bottom tabs: same sections, icons and order as the web widget's tab bar.
class KerabieTabBar extends StatelessWidget {
  const KerabieTabBar({super.key, required this.active, required this.ticketsEnabled, required this.unread, required this.onChanged, required this.palette});

  final KerabieTab active;
  final bool ticketsEnabled;
  final int unread;
  final ValueChanged<KerabieTab> onChanged;
  final KerabiePalette palette;

  static const _tabs = [
    (KerabieTab.home, 'Home', Icons.home_outlined),
    (KerabieTab.chat, 'Chat', Icons.chat_bubble_outline_rounded),
    (KerabieTab.help, 'Help', Icons.help_outline_rounded),
    (KerabieTab.tickets, 'Tickets', Icons.confirmation_number_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.background, border: Border(top: BorderSide(color: palette.border, width: 0.5))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (tab, label, icon) in _tabs)
              if (tab != KerabieTab.tickets || ticketsEnabled)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: tab == active,
                    label: label,
                    child: InkWell(
                      onTap: () => onChanged(tab),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 2,
                              margin: const EdgeInsets.only(bottom: 7),
                              decoration: BoxDecoration(color: tab == active ? palette.accent : Colors.transparent, borderRadius: BorderRadius.circular(1)),
                            ),
                            Badge(
                              isLabelVisible: tab == KerabieTab.chat && unread > 0,
                              label: Text(unread > 9 ? '9+' : '$unread', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: palette.onPrimary)),
                              backgroundColor: palette.primary,
                              child: Icon(icon, size: 22, color: tab == active ? palette.accent : palette.muted),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: tab == active ? FontWeight.w700 : FontWeight.w500,
                                color: tab == active ? palette.accent : palette.muted,
                                fontFamily: palette.fontFamily,
                              ),
                            ),
                          ],
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
