import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../sample_scene.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import 'capture.dart' show kClipDuration;

/// Plays a day's clips back to back, 2 seconds each, like a story reel.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.store, required this.clips, this.start = 0, this.autoplay = true});
  final ClipStore store;
  final List<HourClip> clips;
  final int start;
  final bool autoplay;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late int _i = widget.start;
  late final AnimationController _bar = AnimationController(vsync: this, duration: kClipDuration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  final Map<int, VideoPlayerController> _videos = {};
  bool _muted = false;
  bool _ended = false;

  List<HourClip> get clips => widget.clips;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    _show(_i);
  }

  Future<VideoPlayerController?> _controller(int i) async {
    if (i < 0 || i >= clips.length || clips[i].isSample) return null;
    final existing = _videos[i];
    if (existing != null) return existing;
    final c = VideoPlayerController.file(widget.store.fileOf(clips[i].video));
    _videos[i] = c;
    try {
      await c.initialize();
      await c.setVolume(_muted ? 0 : 1);
    } catch (_) {}
    return c;
  }

  Future<void> _show(int i) async {
    // Stop and release everything except the current and next clip.
    for (final k in _videos.keys.toList()) {
      if (k != i && k != i + 1) {
        _videos.remove(k)?.dispose();
      } else if (k != i) {
        _videos[k]?.pause();
      }
    }
    setState(() {
      _i = i;
      _ended = false;
    });
    _bar.stop();
    _bar.value = 0;
    final c = await _controller(i);
    if (!mounted || _i != i) return;
    if (c != null && c.value.isInitialized) {
      await c.seekTo(Duration.zero);
      if (widget.autoplay) await c.play();
    }
    if (widget.autoplay) _bar.forward(from: 0);
    setState(() {});
    unawaited(_controller(i + 1)); // preload
  }

  void _next() {
    if (_i < clips.length - 1) {
      _show(_i + 1);
    } else {
      _videos[_i]?.pause();
      setState(() => _ended = true);
    }
  }

  void _prev() => _show(_i > 0 ? _i - 1 : 0);

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final c in _videos.values) {
      c.setVolume(_muted ? 0 : 1);
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    _bar.dispose();
    for (final c in _videos.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = clips[_i];
    final day = c.isSample ? '見本' : dayLabel(c.date);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final w = context.size?.width ?? 1;
                d.localPosition.dx < w / 3 ? _prev() : _next();
              },
              child: Stack(fit: StackFit.expand, children: [
                DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(c.hour))),
                _frame(c),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [.6, 1],
                        colors: [Color(0x00000000), Color(0x80000000)]),
                  ),
                ),
                Positioned(top: 10, left: 10, right: 10, child: _bars()),
                Positioned(
                  top: 22,
                  right: 10,
                  child: Row(children: [
                    _chip(_muted ? '音 OFF' : '音 ON', _toggleMute),
                    const SizedBox(width: 6),
                    _chip('閉じる', () => Navigator.of(context).pop()),
                  ]),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${two(c.hour)}:00',
                        style: const TextStyle(fontFamily: kDisplay, fontSize: 48, height: 1, color: Colors.white,
                            shadows: [Shadow(blurRadius: 12, color: Color(0x80000000))])),
                    const SizedBox(height: 4),
                    Text(c.prompt,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(day, style: const TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], color: Color(0xCCFFFFFF), fontSize: 12)),
                  ]),
                ),
                if (_ended) _endCard(),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(HourClip c) {
    if (c.isSample) {
      return AnimatedBuilder(
        animation: _bar,
        builder: (_, child) => Transform.scale(scale: 1 + .09 * _bar.value, child: child),
        child: SampleScene(hour: c.hour, kind: c.sampleScene!),
      );
    }
    final v = _videos[_i];
    if (v == null || !v.value.isInitialized) {
      return Image.file(widget.store.fileOf(c.thumb), fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
    );
  }

  Widget _bars() => AnimatedBuilder(
        animation: _bar,
        builder: (_, _) => Row(children: [
          for (var j = 0; j < clips.length; j++) ...[
            if (j > 0) const SizedBox(width: 3),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: j < _i || _ended ? 1 : (j == _i ? _bar.value : 0),
                  color: Colors.white,
                  backgroundColor: const Color(0x4DFFFFFF),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _chip(String label, VoidCallback onTap) => Material(
        color: const Color(0x73000000),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      );

  Widget _endCard() {
    final first = clips.first;
    return Container(
      color: const Color(0x8C000000),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${clips.length}コマ ・ ${clips.length * 2}秒',
            style: const TextStyle(fontFamily: kDisplay, fontSize: 28, color: Colors.white)),
        const SizedBox(height: 6),
        Text('${first.isSample ? '見本の1日' : dayLabel(first.date)}のVlog',
            style: const TextStyle(color: Color(0xD9FFFFFF))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _show(0),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF1B1830), shape: const StadiumBorder()),
          child: const Text('もう一度', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
