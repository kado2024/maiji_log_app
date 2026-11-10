import 'package:flutter/material.dart';

import 'model.dart';
import 'sample_scene.dart';
import 'sky.dart';
import 'store.dart';

/// Still image for a clip: its thumbnail, the sample illustration,
/// or the sky color of the spot's time when there is no frame.
class ClipStill extends StatelessWidget {
  const ClipStill({super.key, required this.store, required this.clip, required this.spot});
  final SpotStore store;
  final DayClip clip;
  final Spot spot;

  @override
  Widget build(BuildContext context) {
    if (clip.isSample) return SampleScene(month: clip.sampleMonth!);
    final sky = DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(spot.skyHour)));
    if (clip.thumb.isEmpty) return sky;
    return Image.file(store.fileOf(clip.thumb),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) => frame == null && !sync ? sky : child,
        errorBuilder: (_, _, _) => sky);
  }
}

/// Pill-shaped button used on top of camera / video.
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, this.icon, this.label, required this.onTap, this.semantics, this.active = false});
  final IconData? icon;
  final String? label;
  final String? semantics;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics ?? label,
        child: Material(
          color: active ? const Color(0xE6FFFFFF) : const Color(0x73000000),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 14, vertical: label == null ? 10 : 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) Icon(icon, color: active ? const Color(0xFF1B1830) : Colors.white, size: 20),
                if (icon != null && label != null) const SizedBox(width: 6),
                if (label != null)
                  Text(label!,
                      style: TextStyle(
                          color: active ? const Color(0xFF1B1830) : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
}
