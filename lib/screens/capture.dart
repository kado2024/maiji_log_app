import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../sky.dart';
import '../store.dart';
import '../theme.dart';

const kClipDuration = Duration(seconds: 2);

/// Records exactly one 2-second clip for [slot], then lets the user keep it or retake it.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.store, required this.slot, required this.prompt});
  final ClipStore store;
  final DateTime slot;
  final String prompt;

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
  XFile? _thumb;
  VideoPlayerController? _review;

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
    final cam = CameraController(d, ResolutionPreset.high, enableAudio: true);
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
        ? 'カメラかマイクの使用が許可されていません。\n「設定」アプリ → 毎時ログ で、カメラとマイクをオンにしてください。'
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
      _thumb = await cam.takePicture();
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
    for (final f in [_video, _thumb]) {
      if (f != null) {
        final file = File(f.path);
        if (await file.exists()) await file.delete();
      }
    }
    _video = null;
    _thumb = null;
  }

  Future<void> _keep() async {
    if (_video == null || _thumb == null) return;
    setState(() => _phase = _Phase.saving);
    await _review?.pause();
    await widget.store.add(
      slot: widget.slot,
      video: File(_video!.path),
      thumb: File(_thumb!.path),
      prompt: widget.prompt,
    );
    _video = null;
    _thumb = null;
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

  @override
  Widget build(BuildContext context) {
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
                    DecoratedBox(decoration: BoxDecoration(gradient: skyGradient(widget.slot.hour))),
                    _preview(),
                    _topBar(),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${two(widget.slot.hour)}:00',
                            style: const TextStyle(fontFamily: kDisplay, fontSize: 44, height: 1, color: Colors.white,
                                shadows: [Shadow(blurRadius: 10, color: Color(0x80000000))])),
                        Text(widget.prompt,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
                                shadows: [Shadow(blurRadius: 10, color: Color(0x80000000))])),
                      ]),
                    ),
                    if (_phase == _Phase.error) _errorView(),
                  ]),
                ),
              ),
            ),
            SizedBox(height: 132, child: _controls()),
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
          _pill(icon: Icons.close_rounded, label: '閉じる', onTap: () => Navigator.of(context).pop(false)),
          const Spacer(),
          if (_phase == _Phase.ready && _cams.length > 1)
            _pill(icon: Icons.cameraswitch_rounded, label: '切り替え', onTap: _flip),
        ]),
      );

  Widget _pill({required IconData icon, required String label, required VoidCallback onTap}) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0x73000000),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      );

  Widget _errorView() => Container(
        color: const Color(0xB3000000),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(_error,
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
      );

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
          child: Text(_phase == _Phase.saving ? '保存中…' : 'このコマを使う', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);
    }
    final enabled = _phase == _Phase.ready;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Semantics(
        button: true,
        label: '2秒撮影する',
        child: GestureDetector(
          onTap: enabled ? _record : null,
          child: SizedBox(
            width: 84,
            height: 84,
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
                  width: _phase == _Phase.recording ? 34 : 64,
                  height: _phase == _Phase.recording ? 34 : 64,
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
      const SizedBox(height: 10),
      Text(_phase == _Phase.recording ? '撮影中…' : 'タップで2秒だけ撮影',
          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
    ]);
  }
}
