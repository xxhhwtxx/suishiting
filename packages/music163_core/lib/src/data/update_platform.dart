import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../domain/update_models.dart';

abstract interface class UpdatePlatform {
  Future<InstalledAppInfo> installedApp();
  Future<Directory> updateDirectory();
  Future<bool> canInstallPackages();
  Future<void> openInstallSettings();
  Future<void> installApk(String path);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('suishiting/updates');
  @override
  Future<InstalledAppInfo> installedApp() async {
    final info = await channel.invokeMapMethod<String, dynamic>('installedApp');
    final name = info?['versionName'] as String?;
    final code = (info?['versionCode'] as num?)?.toInt();
    if (name == null || code == null) {
      throw const MusicException('无法读取当前版本，请重试。');
    }
    return InstalledAppInfo(versionName: name, versionCode: code);
  }

  @override
  Future<Directory> updateDirectory() async {
    final path = await channel.invokeMethod<String>('updateDirectory');
    if (path == null) throw const MusicException('无法创建更新目录。');
    return Directory(path);
  }

  @override
  Future<bool> canInstallPackages() async =>
      await channel.invokeMethod<bool>('canInstallPackages') ?? false;
  @override
  Future<void> openInstallSettings() async =>
      channel.invokeMethod<void>('openInstallSettings');
  @override
  Future<void> installApk(String path) async {
    try {
      await channel.invokeMethod<void>('installApk', {'path': path});
    } on PlatformException catch (e) {
      throw MusicException(e.message ?? '无法打开系统安装界面。');
    }
  }
}
