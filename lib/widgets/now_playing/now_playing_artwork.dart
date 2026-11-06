/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/async_loader.dart';
import 'package:musify/widgets/flip_card.dart';
import 'package:musify/widgets/now_playing/synced_lyrics_view.dart';
import 'package:musify/widgets/song_artwork.dart';

class NowPlayingArtwork extends StatelessWidget {
  const NowPlayingArtwork({
    super.key,
    required this.size,
    required this.metadata,
    required this.lyricsController,
  });
  final Size size;
  final MediaItem metadata;
  final FlipCardController lyricsController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = size.width;
    final screenHeight = size.height;
    final isLandscape = screenWidth > screenHeight;
    final isDesktop = screenWidth > 800;
    final imageSize = isDesktop
        ? screenHeight * 0.38
        : isLandscape
        ? screenHeight * 0.45
        : screenWidth < 360
        ? screenWidth * 0.75
        : screenWidth < 600
        ? screenWidth * 0.80
        : screenWidth * 0.65;

    const borderRadius = 24.0;

    return FlipCard(
      rotateSide: RotateSide.right,
      onTapFlipping:
          !offlineMode.value && !(metadata.extras?['isLive'] ?? false),
      controller: lyricsController,
      frontWidget: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: SongArtworkWidget(
                metadata: metadata,
                size: imageSize,
                errorWidgetIconSize: size.width / 8,
                borderRadius: borderRadius,
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: _AudioQualityBadge(metadata: metadata),
            ),
          ],
        ),
      ),
      backWidget: Container(
        width: imageSize,
        height: imageSize,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: 2,
            ),
          ],
        ),
        child: _LyricsView(metadata: metadata),
      ),
    );
  }
}

/// Fetches and caches lyrics lazily per song.
class _LyricsView extends StatefulWidget {
  const _LyricsView({required this.metadata});
  final MediaItem metadata;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  String? _resolvedKey;
  late Future<Lyrics?> _lyricsFuture;
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(_LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveIfNeeded();
  }

  void _resolveIfNeeded() {
    final key = '${widget.metadata.artist} - ${widget.metadata.title}';
    if (key == _resolvedKey) return;
    _resolvedKey = key;
    _lyricsFuture = getSongLyricsResult(
      widget.metadata.artist,
      widget.metadata.title,
      duration: widget.metadata.duration,
      album: widget.metadata.album,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget unavailable() => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.text_quote_24_regular,
            size: 48,
            color: colorScheme.onSecondaryContainer.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n!.lyricsNotAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSecondaryContainer,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: AsyncLoader<Lyrics?>(
            future: _lyricsFuture,
            emptyWidget: unavailable(),
            errorBuilder: (ctx, error, stack) => unavailable(),
            builder: (context, lyrics) {
              if (lyrics == null || lyrics.isEmpty) return unavailable();

              return ValueListenableBuilder<bool>(
                valueListenable: syncedLyricsEnabled,
                builder: (context, syncedEnabled, _) {
                  if (lyrics.isSynced && syncedEnabled) {
                    return SyncedLyricsView(
                      lyrics: lyrics,
                      fontScale: _fontScale,
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    physics: const BouncingScrollPhysics(),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      style: TextStyle(
                        fontSize: 18 * _fontScale,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSecondaryContainer,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                      child: Text(formatPlainLyrics(lyrics)),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: colorScheme.surface.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Make lyrics smaller',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  onPressed: _fontScale <= .75
                      ? null
                      : () => setState(() => _fontScale = (_fontScale - .15).clamp(.75, 1.75).toDouble()),
                  icon: const Icon(Icons.remove_rounded),
                ),
                IconButton(
                  tooltip: 'Make lyrics larger',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  onPressed: _fontScale >= 1.75
                      ? null
                      : () => setState(() => _fontScale = (_fontScale + .15).clamp(.75, 1.75).toDouble()),
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: 'Expand lyrics',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  onPressed: () async {
                    final loadedLyrics = await _lyricsFuture;
                    if (!context.mounted ||
                        loadedLyrics == null ||
                        loadedLyrics.isEmpty) {
                      return;
                    }
                    _showExpandedLyrics(context, loadedLyrics);
                  },
                  icon: const Icon(Icons.open_in_full_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showExpandedLyrics(BuildContext context, Lyrics lyrics) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .78),
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
        backgroundColor: colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (context, setDialogState) => SizedBox(
            width: double.infinity,
            height: MediaQuery.sizeOf(context).height * .88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.metadata.title ?? 'Now Playing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.metadata.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close lyrics',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: syncedLyricsEnabled,
                    builder: (context, syncedEnabled, _) {
                      if (lyrics.isSynced && syncedEnabled) {
                        return SyncedLyricsView(lyrics: lyrics, fontScale: _fontScale * 1.15);
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                        physics: const BouncingScrollPhysics(),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20 * _fontScale,
                            fontWeight: FontWeight.w600,
                            height: 1.75,
                          ),
                          textAlign: TextAlign.center,
                          child: Text(formatPlainLyrics(lyrics)),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Make lyrics smaller',
                        onPressed: _fontScale <= .75 ? null : () => setDialogState(() => _fontScale = (_fontScale - .15).clamp(.75, 1.75).toDouble()),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      Text('${(_fontScale * 100).round()}%', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      IconButton(
                        tooltip: 'Make lyrics larger',
                        onPressed: _fontScale >= 1.75 ? null : () => setDialogState(() => _fontScale = (_fontScale + .15).clamp(.75, 1.75).toDouble()),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _AudioQualityInfo = ({int bitrateKbps, String codec});

String _normalizeCodec(String codec) => switch (codec) {
  final c when c.startsWith('opus') => 'Opus',
  final c when c.startsWith('mp4a') => 'AAC',
  final c => c,
};

/// Resolves a song's stored or playback audio quality, or null if unavailable.
Future<_AudioQualityInfo?> _resolveAudioQuality(String ytid) async {
  final offlineSong = getOfflineSongByYtid(ytid);
  final offlineBitrate = offlineSong['audioBitrateKbps'] as int?;
  final offlineCodec = offlineSong['audioCodec'] as String?;
  if (offlineBitrate != null && offlineCodec != null) {
    return (bitrateKbps: offlineBitrate, codec: _normalizeCodec(offlineCodec));
  }
  if (offlineSong.isNotEmpty || offlineMode.value) return null;

  // Free for a song that is playing: the stream it picked is already resolved
  // and cached, so this reads it back instead of asking YouTube again.
  final stream = await fetchBestAudioStream(ytid);
  if (stream == null) return null;

  return (
    bitrateKbps: stream.bitrate.kiloBitsPerSecond.round(),
    codec: _normalizeCodec(stream.audioCodec),
  );
}

/// Shows the current song's resolved audio bitrate and codec.
class _AudioQualityBadge extends StatefulWidget {
  const _AudioQualityBadge({required this.metadata});
  final MediaItem metadata;

  @override
  State<_AudioQualityBadge> createState() => _AudioQualityBadgeState();
}

class _AudioQualityBadgeState extends State<_AudioQualityBadge> {
  String? _resolvedYtid;
  Future<_AudioQualityInfo?>? _infoFuture;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(_AudioQualityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveIfNeeded();
  }

  void _resolveIfNeeded() {
    final ytid = widget.metadata.extras?['ytid']?.toString();
    if (ytid == _resolvedYtid) return;
    _resolvedYtid = ytid;

    final shouldResolve =
        showAudioQualityBadge.value && ytid != null && ytid.isNotEmpty;
    _infoFuture = shouldResolve ? _resolveAudioQuality(ytid) : null;
  }

  @override
  Widget build(BuildContext context) {
    final infoFuture = _infoFuture;
    if (infoFuture == null) return const SizedBox.shrink();

    return FutureBuilder<_AudioQualityInfo?>(
      future: infoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${info.bitrateKbps} kbps • ${info.codec}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
