class AppUpdateInfo {
  final int currentVersionCode;
  final String currentVersionName;
  final int latestVersionCode;
  final String latestVersionName;
  final String apkUrl;
  final bool isForceUpdate;
  final String titleTa;
  final String descTa;
  final String titleEn;
  final String descEn;

  const AppUpdateInfo({
    this.currentVersionCode = 1,
    this.currentVersionName = '2.0.0',
    this.latestVersionCode = 1,
    this.latestVersionName = '2.0.0',
    this.apkUrl = '',
    this.isForceUpdate = false,
    this.titleTa = 'புதிய அப்டேட் வந்துள்ளது!',
    this.descTa = 'செயல்திறன் மற்றும் புதிய வசதிகள் மேம்படுத்தப்பட்டுள்ளன.',
    this.titleEn = 'New Update Available!',
    this.descEn = 'Performance improvements and new features are available.',
  });

  bool get isUpdateAvailable {
    if (latestVersionCode > currentVersionCode) return true;
    return _compareSemanticVersions(latestVersionName, currentVersionName) > 0;
  }

  static int _compareSemanticVersions(String v1, String v2) {
    try {
      final clean1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
      final clean2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');
      final p1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final p2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final num1 = i < p1.length ? p1[i] : 0;
        final num2 = i < p2.length ? p2[i] : 0;
        if (num1 > num2) return 1;
        if (num1 < num2) return -1;
      }
    } catch (_) {}
    return 0;
  }

  factory AppUpdateInfo.fromSettingsMap(Map<String, String> settings, {int currentCode = 1, String currentName = '2.0.0'}) {
    final latestCode = int.tryParse(settings['store_app_version_code'] ?? '1') ?? 1;
    final latestName = settings['store_app_version_name'] ?? '2.0.0';
    final apk = settings['store_apk_url'] ?? '';
    final force = (settings['store_force_update'] ?? 'false').toLowerCase() == 'true';

    return AppUpdateInfo(
      currentVersionCode: currentCode,
      currentVersionName: currentName,
      latestVersionCode: latestCode,
      latestVersionName: latestName,
      apkUrl: apk,
      isForceUpdate: force,
      titleTa: settings['store_update_title_ta'] ?? 'புதிய அப்டேட் வந்துள்ளது!',
      descTa: settings['store_update_desc_ta'] ?? 'செயல்திறன் மற்றும் புதிய வசதிகள் மேம்படுத்தப்பட்டுள்ளன.',
      titleEn: settings['store_update_title_en'] ?? 'New Update Available!',
      descEn: settings['store_update_desc_en'] ?? 'Performance improvements and new features are available.',
    );
  }
}
