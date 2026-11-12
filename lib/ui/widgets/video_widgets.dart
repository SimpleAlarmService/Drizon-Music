import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/download_service.dart';
import '../../services/engines/ytmusic_client.dart';
import '../../services/music_service.dart';
import '../../theme.dart';

/// 16:9 thumbnail with duration and download badges.
class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, required this.item, this.radius = 10});
  final YtmItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final local = context.select<DownloadService, String?>(
        (d) => d.video(item.videoId)?.thumbPath);
    final status =
        context.select<DownloadService, DownloadStatus>((d) => d.videoStatus(item.videoId));
    final progress =
        context.select<DownloadService, double>((d) => d.videoProgress(item.videoId));
    final placeholder = ColoredBox(color: pal.surfaceHigh);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (local != null)
              Image.file(File(local), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
            else
              CachedNetworkImage(
                imageUrl: item.videoThumb(),
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            if (item.durationSec > 0)
              Positioned(
                right: 6,
                bottom: 6,
                child: _Badge(Track.secToString(item.durationSec)),
              ),
            if (status == DownloadStatus.done)
              const Positioned(
                left: 6,
                bottom: 6,
                child: _Badge(null, icon: CupertinoIcons.arrow_down_circle_fill),
              )
            else if (status == DownloadStatus.downloading || status == DownloadStatus.queued)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress == 0 ? null : progress,
                  minHeight: 3,
                  color: kAccent,
                  backgroundColor: Colors.black38,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.icon});
  final String? text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: icon != null
            ? Icon(icon, size: 14, color: Colors.white)
            : Text(text!,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Title + "channel · views" under a thumbnail.
class VideoCaption extends StatelessWidget {
  const VideoCaption({super.key, required this.item, this.maxLines = 2});
  final YtmItem item;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final meta = [item.artist, if (item.views != null) item.views!]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Type.row(pal).copyWith(fontSize: 15, height: 1.25)),
        const SizedBox(height: 2),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Type.caption(pal)),
      ],
    );
  }
}

String qualityLabel(int height) => switch (height) {
      >= 2160 => '4K',
      >= 1440 => '1440p',
      _ => '${height}p',
    };

/// Download / cancel / delete a video. Choosing a quality needs the stream
/// list, so it's fetched first (with a spinner).
Future<void> showVideoDownloadSheet(BuildContext context, YtmItem item) async {
  final downloads = context.read<DownloadService>();
  final status = downloads.videoStatus(item.videoId);

  if (status != DownloadStatus.none && status != DownloadStatus.failed) {
    final done = status == DownloadStatus.done;
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(item.title, maxLines: 2),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              done ? downloads.removeVideo(item.videoId) : downloads.cancelVideo(item.videoId);
            },
            child: Text(done ? '다운로드 삭제' : '다운로드 취소'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
      ),
    );
  }

  final music = context.read<MusicService>();
  final navigator = Navigator.of(context);
  showCupertinoDialog<void>(
    context: context,
    builder: (_) => const Center(child: CupertinoActivityIndicator(radius: 16)),
  );
  List<int> heights;
  try {
    heights = (await music.getVideoStreams(item.videoId)).downloadHeights;
  } catch (_) {
    heights = const [];
  } finally {
    navigator.pop();
  }
  if (!context.mounted) return;

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('화질 선택'),
      message: Text(heights.isEmpty
          ? '이 영상은 내려받을 수 있는 형식이 없어요'
          : '720p 이상은 영상과 소리를 따로 받아 기기에서 합쳐요'),
      actions: [
        for (final h in heights)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              downloads.downloadVideo(item, h);
            },
            child: Text(qualityLabel(h)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
    ),
  );
}
