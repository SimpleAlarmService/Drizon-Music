import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    print('Testing youtube_explode_dart...');
    final manifest = await yt.videos.streams.getManifest('13WxOTSilhY');
    final audio = manifest.audioOnly.withHighestBitrate();
    print('URL: ${audio.url}');
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
  }
}
