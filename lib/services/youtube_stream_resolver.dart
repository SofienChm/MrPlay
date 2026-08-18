import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Category of a failed YouTube stream resolution.
enum YoutubeStreamErrorType {
  notFound,
  unplayable,
  purchaseRequired,
  noStreams,
  network,
  unknown,
}

/// Thrown when a YouTube video cannot be resolved to a playable stream.
class YoutubeStreamException implements Exception {
  const YoutubeStreamException(this.type, this.message, {this.cause});

  final YoutubeStreamErrorType type;
  final String message;
  final Object? cause;

  /// Whether retrying after refreshing the manifest may help.
  bool get retryable =>
      type == YoutubeStreamErrorType.network ||
      type == YoutubeStreamErrorType.unknown ||
      type == YoutubeStreamErrorType.noStreams;

  @override
  String toString() => message;
}

/// Basic video metadata, used to populate the mini player / now-playing.
class YoutubeVideoInfo {
  const YoutubeVideoInfo({
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
  });

  final String title;
  final String channel;
  final String thumbnailUrl;
}

/// A playable direct stream for a YouTube video.
class YoutubeStreamResolution {
  const YoutubeStreamResolution({
    required this.videoId,
    required this.url,
    required this.qualityLabel,
    required this.isHls,
  });

  final String videoId;
  final Uri url;
  final String qualityLabel;
  final bool isHls;

  @override
  String toString() =>
      'YoutubeStreamResolution($videoId, $qualityLabel, hls: $isHls)';
}

/// Resolves YouTube videos to direct playable stream URLs.
///
/// Direct stream URLs expire, so every playback resolves a fresh manifest.
/// The primary clients are merged so a higher quality muxed stream can be
/// selected, and a fallback chain is tried when the primary clients fail.
class YoutubeStreamResolver {
  YoutubeStreamResolver({YoutubeExplode? youtubeExplode})
      : _youtube = youtubeExplode ?? YoutubeExplode();

  final YoutubeExplode _youtube;

  static const List<YoutubeApiClient> _primaryClients = [
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.androidVr,
  ];

  static const List<YoutubeApiClient> _fallbackClients = [
    YoutubeApiClient.tv,
  ];

  /// Resolves [videoIdOrUrl] (an 11-char id or a YouTube watch URL) to the
  /// highest quality muxed stream available.
  Future<YoutubeStreamResolution> resolve(dynamic videoIdOrUrl) async {
    final videoId = VideoId.fromString(videoIdOrUrl);

    StreamManifest manifest;
    try {
      manifest = await _getManifest(videoId, _primaryClients);
    } on YoutubeStreamException catch (e) {
      if (e.type == YoutubeStreamErrorType.purchaseRequired) rethrow;
      manifest = await _getManifest(videoId, _fallbackClients);
    }
    return _selectStream(videoId, manifest);
  }

  Future<StreamManifest> _getManifest(
    VideoId videoId,
    List<YoutubeApiClient> clients,
  ) async {
    try {
      return await _youtube.videos.streams
          .getManifest(videoId, ytClients: clients);
    } on VideoRequiresPurchaseException catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.purchaseRequired,
        'This video requires a rental or premium purchase.',
        cause: e,
      );
    } on VideoUnavailableException catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.notFound,
        'This video is no longer available.',
        cause: e,
      );
    } on VideoUnplayableException catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.unplayable,
        'This video cannot be played here.',
        cause: e,
      );
    } on TransientFailureException catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.network,
        'YouTube could not be reached. Check your connection and try again.',
        cause: e,
      );
    } on YoutubeExplodeException catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.unknown,
        'Unable to extract a playable stream.',
        cause: e,
      );
    } catch (e) {
      throw YoutubeStreamException(
        YoutubeStreamErrorType.unknown,
        'Unable to extract a playable stream.',
        cause: e,
      );
    }
  }

  YoutubeStreamResolution _selectStream(
    VideoId videoId,
    StreamManifest manifest,
  ) {
    final muxed = manifest.muxed;
    if (muxed.isNotEmpty) {
      final stream = muxed.withHighestBitrate();
      return YoutubeStreamResolution(
        videoId: videoId.value,
        url: stream.url,
        qualityLabel: stream.qualityLabel,
        isHls: false,
      );
    }

    final hlsMuxed = manifest.hls.whereType<HlsMuxedStreamInfo>().toList();
    if (hlsMuxed.isNotEmpty) {
      final stream = hlsMuxed.withHighestBitrate();
      return YoutubeStreamResolution(
        videoId: videoId.value,
        url: stream.url,
        qualityLabel: stream.qualityLabel,
        isHls: true,
      );
    }

    throw const YoutubeStreamException(
      YoutubeStreamErrorType.noStreams,
      'No playable stream found for this video.',
    );
  }

  /// Fetches basic metadata (title / channel / thumbnail) for a video.
  /// Returns null when the metadata request fails (the caller should fall back
  /// to whatever title it already has).
  Future<YoutubeVideoInfo?> fetchInfo(dynamic videoIdOrUrl) async {
    try {
      final videoId = VideoId.fromString(videoIdOrUrl);
      final video = await _youtube.videos.get(videoId);
      return YoutubeVideoInfo(
        title: video.title,
        channel: video.author,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => _youtube.close();
}
