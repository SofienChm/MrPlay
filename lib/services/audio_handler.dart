import 'package:just_audio/just_audio.dart';

class MrPlayAudioHandler {
  final AudioPlayer player = AudioPlayer(useProxyForRequestHeaders: false);

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> stop() async {
    await player.stop();
  }
  Future<void> seek(Duration position) => player.seek(position);
  void dispose() => player.dispose();

  Future<void> setSource(AudioSource source) async {
    await player.setAudioSource(source);
  }
}
