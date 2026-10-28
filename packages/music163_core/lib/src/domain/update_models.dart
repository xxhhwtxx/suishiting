import 'package:flutter/foundation.dart';

enum UpdateStatus {
  idle,
  checking,
  noRelease,
  upToDate,
  available,
  downloading,
  ready,
  permissionRequired,
  installing,
  failed,
}

@immutable
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.versionName,
    required this.versionCode,
  });
  final String versionName;
  final int versionCode;
}

@immutable
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.size,
    required this.pageUrl,
    required this.downloadUrl,
    required this.sha256,
    required this.assetId,
  });
  final String version;
  final String notes;
  final int size;
  final Uri pageUrl;
  final Uri downloadUrl;
  final String sha256;
  final int assetId;
}

/// Stable releases use vMAJOR.MINOR.PATCH, optionally with a numeric build.
int compareReleaseVersions(String a, String b) {
  List<int> parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Unsupported version');
    return [for (var i = 1; i <= 4; i++) int.parse(match[i] ?? '0')];
  }

  final left = parse(a), right = parse(b);
  for (var i = 0; i < 4; i++) {
    final result = left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return 0;
}
