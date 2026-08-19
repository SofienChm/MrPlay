import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  final int versionCode;
  final String downloadUrl;

  const AppUpdate({required this.versionCode, required this.downloadUrl});
}

/// Checks Firebase Remote Config for a newer build than the installed one and
/// returns the download URL when an update is available. Degrades silently to
/// `null` when Firebase isn't configured or the network is unavailable.
class UpdateCheckService {
  UpdateCheckService._();

  static final UpdateCheckService instance = UpdateCheckService._();

  static const String _versionCodeKey = 'latest_version_code';
  static const String _downloadUrlKey = 'apk_url';

  Future<AppUpdate?> check() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 15),
          minimumFetchInterval: Duration.zero,
        ),
      );
      await remoteConfig.fetchAndActivate();

      final latestCode = remoteConfig.getInt(_versionCodeKey);
      final downloadUrl = remoteConfig.getString(_downloadUrlKey);
      if (latestCode <= 0 || downloadUrl.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      if (latestCode > currentCode) {
        return AppUpdate(versionCode: latestCode, downloadUrl: downloadUrl);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
