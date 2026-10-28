package app.music163.music163_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    private fun installedInfo() = packageManager.getPackageInfo(packageName, 0)

    private fun updateDirectory(): File = File(cacheDir, "updates").also { it.mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "suishiting/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installedApp" -> {
                            val info = installedInfo()
                            @Suppress("DEPRECATION")
                            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                            result.success(mapOf("versionName" to info.versionName, "versionCode" to code))
                        }
                        "updateDirectory" -> result.success(updateDirectory().canonicalPath)
                        "canInstallPackages" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                        "openInstallSettings" -> {
                            if (Build.VERSION.SDK_INT >= 26) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            }
                            result.success(null)
                        }
                        "installApk" -> {
                            val path = call.argument<String>("path") ?: throw IllegalArgumentException("安装包路径无效。")
                            installOwnUpdate(File(path))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    val message = if (e is IllegalArgumentException) e.message else "无法打开系统更新界面，请重试。"
                    result.error("UPDATE_ERROR", message, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun installOwnUpdate(candidate: File) {
        val file = candidate.canonicalFile
        require(file.parentFile == updateDirectory().canonicalFile &&
            Regex("update-[0-9]+\\.apk").matches(file.name) && file.isFile) { "安装包路径无效，请重新下载。" }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("安装包无法识别，请重新下载。")
        val current = packageManager.getPackageInfo(packageName, flags)
        require(archive.packageName == packageName) { "安装包不属于随时听，已停止安装。" }
        val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        require(newCode > oldCode) { "安装包不是更新版本，请重新检查更新。" }
        val oldSigners = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
        val newSigners = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        require(!oldSigners.isNullOrEmpty() && !newSigners.isNullOrEmpty() &&
            oldSigners.map { it.toCharsString() }.toSet() == newSigners.map { it.toCharsString() }.toSet()) {
            "新版签名与当前应用不一致，请联系发布者。"
        }
        require(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()) { "请先允许随时听安装应用。" }
        val uri = FileProvider.getUriForFile(this, "$packageName.updatefiles", file)
        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }
}
