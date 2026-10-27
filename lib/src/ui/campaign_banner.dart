import 'package:flutter/material.dart';

import '../campaigns.dart';
import '../config.dart';
import 'palette.dart';

/// The proactive message shown above the launcher, like the web widget's campaign bubble.
class KerabieCampaignBanner extends StatelessWidget {
  const KerabieCampaignBanner({
    super.key,
    required this.campaign,
    required this.palette,
    required this.name,
    required this.position,
    required this.onOpen,
    required this.onCta,
    required this.onDismiss,
  });

  final KerabieCampaign campaign;
  final KerabiePalette palette;
  final String name;
  final KerabiePosition position;

  /// Tapping the message, or Reply, opens the chat.
  final VoidCallback onOpen;

  /// Tapping the campaign's button.
  final VoidCallback onCta;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final left = position == KerabiePosition.bottomLeft || position == KerabiePosition.topLeft;
    final accent = palette.primary;
    final hasCover = campaign.imageUrl != null;
    return SafeArea(
      child: Align(
        alignment: left ? Alignment.bottomLeft : Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width * 0.9).clamp(0, 300)),
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: const Color(0x24000000),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasCover)
                        InkWell(
                          onTap: onOpen,
                          child: AspectRatio(
                            aspectRatio: 800 / 420,
                            child: Image.network(campaign.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: onOpen,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                                      alignment: Alignment.center,
                                      child: Text(
                                        (name.trim().isEmpty ? '?' : name.trim()[0]).toUpperCase(),
                                        style: TextStyle(color: palette.onPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF64748B))),
                                          const SizedBox(height: 2),
                                          Text(campaign.message, style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF1E293B))),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (campaign.ctaLabel != null)
                              SizedBox(
                                width: double.infinity,
                                height: 36,
                                child: Material(
                                  borderRadius: BorderRadius.circular(9),
                                  clipBehavior: Clip.antiAlias,
                                  color: palette.launcherColor ?? (palette.gradient ? null : accent),
                                  child: Ink(
                                    decoration: BoxDecoration(color: accent, gradient: palette.launcherColor == null ? palette.brandGradient : null),
                                    child: InkWell(
                                      onTap: onCta,
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          child: Text(campaign.ctaLabel!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: palette.onLauncher, fontSize: 13, fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              InkWell(onTap: onOpen, child: Text('Reply →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    right: hasCover ? 8 : 10,
                    child: Semantics(
                      button: true,
                      label: 'Dismiss',
                      child: InkWell(
                        onTap: onDismiss,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: hasCover ? const BoxDecoration(shape: BoxShape.circle, color: Color(0x73000000)) : null,
                          alignment: Alignment.center,
                          child: Icon(Icons.close_rounded, size: hasCover ? 14 : 16, color: hasCover ? Colors.white : const Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
