import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';

void main() async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streams.getManifest('13WxOTSilhY');
    final audio = manifest.audioOnly.withHighestBitrate();
    print('URL: ${audio.url}');
    
    // Testing headers
    final client = HttpClient();
    final req = await client.getUrl(audio.url);
    // req.headers.add('User-Agent', 'Mozilla/5.0 ...');
    final res = await req.close();
    print('Status (No UA): ${res.statusCode}');

    final req2 = await client.getUrl(audio.url);
    req2.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final res2 = await req2.close();
    print('Status (Chrome UA): ${res2.statusCode}');

  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
  }
}
