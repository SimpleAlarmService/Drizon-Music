import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/track.dart';
import 'package:provider/provider.dart';
import '../../services/library_service.dart';
import '../../services/metadata_service.dart';
import '../../theme.dart';

/// Square album art. YouTube thumbnails are 16:9, so they are centre-cropped.
/// With [hiRes] it first tries the 1280px thumbnail and falls back to the stored one.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    this.size,
    this.radius = 8,
    this.hiRes = false,
  });

  final Track? track;
  final double? size;
  final double radius;
  final bool hiRes;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final placeholder = Container(
      color: pal.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.music_note,
          color: pal.secondaryLabel, size: size == null ? 32 : size! * 0.4),
    );

    final t = track;
    // Album cover from YouTube Music (or matched later) beats a video frame.
    final art = context.select<MetadataService, String?>(
        (m) => t == null ? null : m.artFor(t));
    Widget image;
    if (t == null || (t.thumbnail.isEmpty && art == null)) {
      image = placeholder;
    } else {
      Widget plain() => CachedNetworkImage(
            imageUrl: t.thumbnail,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
      Widget frame() => hiRes
          ? CachedNetworkImage(
              imageUrl: 'https://i.ytimg.com/vi/${t.videoId}/maxresdefault.jpg',
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => plain(),
            )
          : plain();
      image = art == null
          ? frame()
          : CachedNetworkImage(
              imageUrl: art,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => frame(),
            );
    }

    final box = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: image),
    );
    return size == null ? AspectRatio(aspectRatio: 1, child: box) : box;
  }
}

/// Cover for a library [Collection]: gradient tiles for the built-ins,
/// a 2×2 mosaic (or single image) for playlists.
class CollectionArtwork extends StatelessWidget {
  const CollectionArtwork({
    super.key,
    required this.collection,
    this.size,
    this.radius = 6,
  });

  final Collection collection;
  final double? size;
  final double radius;

  static const _palettes = <List<Color>>[
    [Color(0xFF7F7FD5), Color(0xFF86A8E7)],
    [Color(0xFFF7971E), Color(0xFFFFD200)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFEE0979), Color(0xFFFF6A00)],
    [Color(0xFF4568DC), Color(0xFFB06AB3)],
  ];

  @override
  Widget build(BuildContext context) {
    final tracks = collection.tracks;
    Widget content;
    switch (collection.kind) {
      case CollectionKind.liked:
        content = _gradient(const [Color(0xFFFF5F6D), Color(0xFFFA2D48)],
            CupertinoIcons.heart_fill);
      case CollectionKind.history:
        content = _gradient(const [Color(0xFF396AFC), Color(0xFF2948FF)],
            CupertinoIcons.clock_fill);
      case CollectionKind.downloads:
        content = _gradient(const [Color(0xFF34C759), Color(0xFF0E8A3E)],
            CupertinoIcons.arrow_down_circle_fill);
      case CollectionKind.playlist:
        if (tracks.isEmpty) {
          final colors =
              _palettes[collection.id.hashCode.abs() % _palettes.length];
          content = _gradient(colors, CupertinoIcons.music_note_list);
        } else if (tracks.length < 4) {
          content = Artwork(track: tracks.first, radius: 0);
        } else {
          Widget cell(int i) => Expanded(child: Artwork(track: tracks[i], radius: 0));
          content = Column(children: [
            Expanded(child: Row(children: [cell(0), cell(1)])),
            Expanded(child: Row(children: [cell(2), cell(3)])),
          ]);
        }
    }
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: content),
    );
    return size == null ? AspectRatio(aspectRatio: 1, child: box) : box;
  }

  Widget _gradient(List<Color> colors, IconData icon) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (_, c) => Icon(icon,
                color: Colors.white.withValues(alpha: 0.92),
                size: c.biggest.shortestSide * 0.38),
          ),
        ),
      );
}
