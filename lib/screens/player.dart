import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model.dart';
import '../sample_scene.dart';
import '../schedule.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Plays one spot's days back to back: the same time, day after day.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.store,
    required this.spot,
    required this.clips,
    this.start = 0,
    this.secondsPerClip = 1.0,
    this.autoplay = true,
  });
  final SpotStore store;
  final Spot spot;
  final List<DayClip> clips;
  final int start;
  final double secondsPerClip;
  final bool autoplay;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late int _i = widget.start.clamp(0, widget.clips.length - 1);
  late double _speed = widget.secondsPerClip;
  late final AnimationController _bar = AnimationController(vsync: this, duration: _dur)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  final Map<int, VideoPlayerController> _videos = {};
  bool _muted = true;
  bool _ended = false;

  Duration get _dur => Duration(milliseconds: (_speed * 1000).round());
  List<DayClip> get clips => widget.clips;

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
    unawaited(_controller(i + 1));
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

  void _cycleSpeed() {
    final k = kSpeeds.indexOf(_speed);
    setState(() => _speed = kSpeeds[(k + 1) % kSpeeds.length]);
    _bar.duration = _dur;
    if (!_ended) _bar.forward(from: _bar.value);
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
    final s = widget.spot;
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
                DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(s.skyHour))),
                _frame(c),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .14, .55, 1],
                        colors: [Color(0x73000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)]),
                  ),
                ),
                Positioned(top: 10, left: 12, right: 12, child: _progress()),
                Positioned(
                  top: 24,
                  right: 10,
                  child: Row(children: [
                    GlassPill(label: speedLabel(_speed), onTap: _cycleSpeed, semantics: '再生の速さを変える'),
                    const SizedBox(width: 6),
                    if (!c.isSample) ...[
                      GlassPill(label: _muted ? '音 OFF' : '音 ON', onTap: _toggleMute),
                      const SizedBox(width: 6),
                    ],
                    GlassPill(label: '閉じる', onTap: () => Navigator.of(context).pop()),
                  ]),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s.timeLabel}  ${s.name}',
                        style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(c.isSample ? '${c.sampleMonth}月' : dayLabel(c.date),
                        style: const TextStyle(fontFamily: kDisplay, fontSize: 44, height: 1.05, color: Colors.white,
                            shadows: [Shadow(blurRadius: 12, color: Color(0x80000000))])),
                    if (!c.isSample)
                      Text(c.date.substring(0, 4),
                          style: const TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], color: Color(0xCCFFFFFF), fontSize: 12)),
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

  Widget _frame(DayClip c) {
    if (c.isSample) {
      return AnimatedBuilder(
        animation: _bar,
        builder: (_, child) => Transform.scale(scale: 1 + .03 * _bar.value, child: child),
        child: SampleScene(month: c.sampleMonth!),
      );
    }
    final v = _videos[_i];
    if (v == null || !v.value.isInitialized) {
      return ClipStill(store: widget.store, clip: c, spot: widget.spot);
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
    );
  }

  Widget _progress() => AnimatedBuilder(
        animation: _bar,
        builder: (_, _) {
          final f = _ended ? 1.0 : (_i + _bar.value) / clips.length;
          return Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    minHeight: 3, value: f, color: Colors.white, backgroundColor: const Color(0x4DFFFFFF)),
              ),
            ),
            const SizedBox(width: 8),
            Text('${_i + 1} / ${clips.length}',
                style: const TextStyle(fontFamily: kMono, fontFamilyFallback: [kBody], color: Colors.white, fontSize: 11)),
          ]);
        },
      );

  Widget _endCard() {
    final first = clips.first, last = clips.last;
    final range = first.isSample ? '1月 〜 12月' : '${dayLabel(first.date)} 〜 ${dayLabel(last.date)}';
    return Container(
      color: const Color(0x8C000000),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(first.isSample ? '12か月' : '${clips.length}日分',
            style: const TextStyle(fontFamily: kDisplay, fontSize: 30, color: Colors.white)),
        const SizedBox(height: 6),
        Text('${widget.spot.timeLabel} の変化  $range', style: const TextStyle(color: Color(0xD9FFFFFF))),
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
