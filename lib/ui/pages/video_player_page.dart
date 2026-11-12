import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/track.dart';
import '../../services/download_service.dart';
import '../../services/engines/ytmusic_client.dart';
import '../../services/music_service.dart';
import '../../services/player_service.dart';
import '../glass/liquid_glass.dart';
import '../widgets/video_widgets.dart';

/// Plays a music video / stage / fancam: from disk when downloaded, otherwise
/// streamed (HLS when available, for adaptive quality).
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.item});
  final YtmItem item;

  static Route<void> route(YtmItem item) => CupertinoPageRoute<void>(
      fullscreenDialog: true, builder: (_) => VideoPlayerPage(item: item));

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  double? _drag;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Music and video shouldn't play over each other.
    final player = context.read<PlayerService>();
    if (player.isPlaying) player.togglePlay();
    _open();
  }

  Future<void> _open() async {
    try {
      final local = context.read<DownloadService>().video(widget.item.videoId);
      VideoPlayerController c;
      if (local != null && File(local.path).existsSync()) {
        c = VideoPlayerController.file(File(local.path));
      } else {
        final streams = await context.read<MusicService>().getVideoStreams(widget.item.videoId);
        final url = streams.playbackUrl ?? (throw Exception('재생할 수 있는 형식이 없어요'));
        c = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: streams.headers);
      }
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _controller = c);
      await c.play();
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '영상을 불러오지 못했어요');
      debugPrint('[Video] ${widget.item.videoId}: $e');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false) && _drag == null) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    if (on) {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _videoArea();
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _setFullscreen(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _fullscreen
            ? Center(child: video)
            : SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    video,
                    Expanded(child: _Details(item: widget.item)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _videoArea() {
    final c = _controller;
    final ratio = (c != null && c.value.isInitialized && c.value.aspectRatio > 0)
        ? c.value.aspectRatio
        : 16 / 9;
    Widget content;
    if (_error != null) {
      content = Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)));
    } else if (c == null || !c.value.isInitialized) {
      content = Stack(fit: StackFit.expand, children: [
        Opacity(opacity: 0.5, child: VideoThumb(item: widget.item, radius: 0)),
        const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
      ]);
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(fit: StackFit.expand, children: [
          VideoPlayer(c),
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(ignoring: !_controlsVisible, child: _controls(c)),
          ),
        ]),
      );
    }
    return AspectRatio(aspectRatio: ratio, child: content);
  }

  Widget _controls(VideoPlayerController c) {
    final v = c.value;
    final total = v.duration.inMilliseconds;
    final value = _drag ?? (total == 0 ? 0.0 : (v.position.inMilliseconds / total).clamp(0.0, 1.0));
    final label = const TextStyle(
        color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black38, Colors.transparent, Colors.black54],
        ),
      ),
      child: Stack(children: [
        Center(
          child: v.isBuffering
              ? const CupertinoActivityIndicator(color: Colors.white, radius: 16)
              : IconButton(
                  iconSize: 56,
                  color: Colors.white,
                  icon: Icon(v.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill),
                  onPressed: () {
                    v.isPlaying ? c.pause() : c.play();
                    _scheduleHide();
                  },
                ),
        ),
        Positioned(
          left: 12,
          right: 4,
          bottom: 0,
          child: Row(children: [
            Text(Track.secToString(Duration(milliseconds: (value * total).round()).inSeconds),
                style: label),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value.toDouble(),
                  onChanged: total == 0 ? null : (x) => setState(() => _drag = x),
                  onChangeEnd: (x) {
                    c.seekTo(Duration(milliseconds: (x * total).round()));
                    setState(() => _drag = null);
                    _scheduleHide();
                  },
                ),
              ),
            ),
            Text(Track.secToString(v.duration.inSeconds), style: label),
            IconButton(
              color: Colors.white,
              icon: Icon(_fullscreen
                  ? CupertinoIcons.fullscreen_exit
                  : CupertinoIcons.fullscreen),
              onPressed: () => _setFullscreen(!_fullscreen),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.item});
  final YtmItem item;

  @override
  Widget build(BuildContext context) {
    final status = context.select<DownloadService, DownloadStatus>((d) => d.videoStatus(item.videoId));
    final progress = context.select<DownloadService, double>((d) => d.videoProgress(item.videoId));
    final height = context.select<DownloadService, int?>((d) => d.video(item.videoId)?.height);
    final error = context.select<DownloadService, String?>((d) => d.videoError(item.videoId));

    final downloadLabel = switch (status) {
      DownloadStatus.done => '다운로드됨 · ${qualityLabel(height ?? 0)}',
      DownloadStatus.downloading => '다운로드 중 ${(progress * 100).round()}%',
      DownloadStatus.queued => '대기 중',
      DownloadStatus.failed => '다시 시도',
      DownloadStatus.none => '다운로드',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(item.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 6),
        Text([item.artist, if (item.views != null) item.views!].join(' · '),
            style: const TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: _Action(
              icon: status == DownloadStatus.done
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.arrow_down_circle,
              label: downloadLabel,
              onTap: () => showVideoDownloadSheet(context, item),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Action(
              icon: CupertinoIcons.music_note,
              label: '음악으로 듣기',
              onTap: () {
                final t = item.toTrack();
                context.read<PlayerService>().playTrack(t, queue: [t]);
                Navigator.of(context).pop();
              },
            ),
          ),
        ]),
        if (status == DownloadStatus.failed && error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
          ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassPressable(
        depth: 0.05,
        onTap: onTap,
        builder: (context, press, child) => LiquidGlass(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          shadow: false,
          highlight: 1 + press * 0.5,
          child: child,
        ),
        child: SizedBox(
          height: 48,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
}
