// ============================================================
// update_info.dart — Model data informasi update
// ============================================================

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool hasUpdate;
  final String apkName;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.hasUpdate,
    this.apkName = '',
  });

  @override
  String toString() =>
      'UpdateInfo(v$latestVersion, hasUpdate=$hasUpdate, apk=$apkName)';
}
