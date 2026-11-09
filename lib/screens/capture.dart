import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../exporter.dart';
import '../model.dart';
import '../sky.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

const kClipDuration = Duration(seconds: 2);

/// Records the one 2-second clip of [spot] for [date]. The previous day's
/// frame can be laid over the camera (framing guide) to keep the composition.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.store, required this.spot, required this.date, this.media = const SequenceExporter()});
  final SpotStore store;
  final Spot spot;
  final String date;
  final SequenceExporter media;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

enum _Phase { starting, ready, recording, review, saving, error }

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<CameraDescription> _cams = [];
  int _camIndex = 0;
  CameraController? _cam;
  _Phase _phase = _Phase.starting;
  String _error = '';
  late final AnimationController _progress = AnimationController(vsync: this, duration: kClipDuration);
  XFile? _video;
  VideoPlayerController? _review;
  late final DayClip? _prev = widget.store.previousFrame(widget.spot.id, widget.date);
  late bool _ghost = _prev != null;
  double _ghostOpacity = .4;
  bool _grid = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (_phase == _Phase.recording) _progress.stop();
      cam.dispose();
      _cam = null;
      if (_phase == _Phase.recording) _phase = _Phase.ready;
    } else if (state == AppLifecycleState.resumed && _phase != _Phase.review) {
      _open(_cams[_camIndex]);
    }
  }

  Future<void> _start() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) return _fail('この端末ではカメラが見つかりませんでした。');
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _camIndex = back < 0 ? 0 : back;
      await _open(_cams[_camIndex]);
    } on CameraException catch (e) {
      _failFrom(e);
    }
  }

  Future<void> _open(CameraDescription d) async {
    final old = _cam;
    _cam = null;
    if (mounted) setState(() => _phase = _Phase.starting);
    await old?.dispose();
    final cam = CameraController(d, ResolutionPreset.veryHigh, enableAudio: true);
    try {
      await cam.initialize();
      await cam.prepareForVideoRecording();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _phase = _Phase.ready;
      });
    } on CameraException catch (e) {
      await cam.dispose();
      _failFrom(e);
    }
  }

  void _failFrom(CameraException e) {
    final denied = e.code.contains('AccessDenied') || e.code.contains('AccessRestricted');
    _fail(denied
        ? 'カメラかマイクの使用が許可されていません。\n「設定」アプリ → おなじ時刻 で、カメラとマイクをオンにしてください。'
        : 'カメラを起動できませんでした（${e.code}）。');
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = msg;
    });
  }

  Future<void> _record() async {
    final cam = _cam;
    if (cam == null || _phase != _Phase.ready) return;
    try {
      setState(() => _phase = _Phase.recording);
      await cam.startVideoRecording();
      _progress.forward(from: 0);
      await Future.delayed(kClipDuration);
      if (!mounted || _cam != cam) return;
      _video = await cam.stopVideoRecording();
      final rv = VideoPlayerController.file(File(_video!.path));
      await rv.initialize();
      await rv.setLooping(true);
      await rv.play();
      if (!mounted) {
        rv.dispose();
        return;
      }
      setState(() {
        _review = rv;
        _phase = _Phase.review;
      });
    } on CameraException catch (e) {
      _failFrom(e);
    }
  }

  Future<void> _retake() async {
    final rv = _review;
    _review = null;
    await rv?.dispose();
    await _discard();
    _progress.value = 0;
    if (mounted) setState(() => _phase = _cam == null ? _Phase.starting : _Phase.ready);
    if (_cam == null) _open(_cams[_camIndex]);
  }

  Future<void> _discard() async {
    final f = _video;
    if (f != null) {
      final file = File(f.path);
      if (await file.exists()) await file.delete();
    }
    _video = null;
  }

  Future<void> _keep() async {
    final v = _video;
    if (v == null) return;
    setState(() => _phase = _Phase.saving);
    await _review?.pause();
    // A still from the recorded video itself, so the framing guide lines up
    // exactly with what the next recording will look like.
    final thumbPath = '${v.path}.jpg';
    final ok = await widget.media.frame(v.path, thumbPath);
    await widget.store.add(
      spotId: widget.spot.id,
      date: widget.date,
      video: File(v.path),
      thumb: ok ? File(thumbPath) : null,
    );
    _video = null;
    if (mounted) Navigator.of(context).pop(true);
  }

  void _flip() {
    if (_cams.length < 2 || _phase != _Phase.ready) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    _open(_cams[_camIndex]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    _progress.dispose();
    _cam?.dispose();
    _review?.dispose();
    if (_phase != _Phase.saving) _discard();
    super.dispose();
  }

  bool get _live => _phase == _Phase.ready || _phase == _Phase.recording || _phase == _Phase.starting;

  @override
  Widget build(BuildContext context) {
    final s = widget.spot;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(fit: StackFit.expand, children: [
                    DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(s.skyHour))),
                    _preview(),
                    if (_ghost && _prev != null && _live)
                      IgnorePointer(
                        child: Opacity(
                          opacity: _ghostOpacity,
                          child: Image.file(widget.store.fileOf(_prev.thumb),
                              fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                        ),
                      ),
                    if (_grid && _live) const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                    _topBar(),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.timeLabel,
                            style: const TextStyle(fontFamily: kDisplay, fontSize: 44, height: 1, color: Colors.white,
                                shadows: [Shadow(blurRadius: 10, color: Color(0x80000000))])),
                        Text('${dayLabel(widget.date)}  ${s.name}',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
                                shadows: [Shadow(blurRadius: 10, color: Color(0x80000000))])),
                        if (_prev != null && _live)
                          Text(_ghost ? '前回（${dayLabel(_prev.date)}）の構図を重ねています' : '前回：${dayLabel(_prev.date)}',
                              style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12,
                                  shadows: [Shadow(blurRadius: 8, color: Color(0x80000000))])),
                      ]),
                    ),
                    if (_phase == _Phase.error) _errorView(),
                  ]),
                ),
              ),
            ),
            SizedBox(height: 172, child: _controls()),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (_phase == _Phase.review || _phase == _Phase.saving) {
      final rv = _review;
      if (rv == null) return const SizedBox();
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: rv.value.size.width, height: rv.value.size.height, child: VideoPlayer(rv)),
      );
    }
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final ps = cam.value.previewSize; // reported in landscape
    final w = ps?.height ?? 9, h = ps?.width ?? 16;
    return FittedBox(fit: BoxFit.cover, child: SizedBox(width: w, height: h, child: CameraPreview(cam)));
  }

  Widget _topBar() => Positioned(
        top: 10,
        left: 10,
        right: 10,
        child: Row(children: [
          GlassPill(icon: Icons.close_rounded, semantics: '閉じる', onTap: () => Navigator.of(context).pop(false)),
          const Spacer(),
          if (_phase == _Phase.ready && _cams.length > 1)
            GlassPill(icon: Icons.cameraswitch_rounded, semantics: 'カメラ切り替え', onTap: _flip),
        ]),
      );

  Widget _errorView() => Container(
        color: const Color(0xB3000000),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(_error,
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
      );

  Widget _guides() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GlassPill(
          icon: Icons.layers_outlined,
          label: '前回と重ねる',
          active: _ghost,
          onTap: _prev == null ? null : () => setState(() => _ghost = !_ghost),
        ),
        const SizedBox(width: 8),
        GlassPill(icon: Icons.grid_3x3_rounded, label: 'グリッド', active: _grid, onTap: () => setState(() => _grid = !_grid)),
        if (_ghost && _prev != null)
          SizedBox(
            width: 110,
            child: Slider(
              value: _ghostOpacity,
              min: .15,
              max: .75,
              activeColor: Colors.white,
              inactiveColor: const Color(0x40FFFFFF),
              semanticFormatterCallback: (v) => '重ねる濃さ ${(v * 100).round()}%',
              onChanged: (v) => setState(() => _ghostOpacity = v),
            ),
          ),
      ]);

  Widget _controls() {
    if (_phase == _Phase.review || _phase == _Phase.saving) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton(
          onPressed: _phase == _Phase.saving ? null : _retake,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0x80FFFFFF)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          child: const Text('撮り直す', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 14),
        FilledButton(
          onPressed: _phase == _Phase.saving ? null : _keep,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.dark.accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
          child: Text(_phase == _Phase.saving ? '保存中…' : '今日のぶんにする', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);
    }
    final enabled = _phase == _Phase.ready;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _guides(),
      const SizedBox(height: 10),
      Semantics(
        button: true,
        label: '2秒撮影する',
        child: GestureDetector(
          onTap: enabled ? _record : null,
          child: SizedBox(
            width: 76,
            height: 76,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (_, _) => Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: _phase == _Phase.recording ? _progress.value : 1,
                    strokeWidth: 5,
                    color: _phase == _Phase.recording ? const Color(0xFFFF3B30) : Colors.white,
                    backgroundColor: const Color(0x40FFFFFF),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _phase == _Phase.recording ? 30 : 58,
                  height: _phase == _Phase.recording ? 30 : 58,
                  decoration: BoxDecoration(
                    color: enabled || _phase == _Phase.recording ? const Color(0xFFFF3B30) : const Color(0x66FF3B30),
                    borderRadius: BorderRadius.circular(_phase == _Phase.recording ? 8 : 40),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(_phase == _Phase.recording ? '撮影中…' : 'タップで2秒撮影', style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), p);
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
