# 发布与应用内更新

默认更新源为公开仓库 `xxhhwtxx/suishiting` 的最新正式 Release。应用通过 GitHub API 获取版本、安装包地址、大小和 SHA-256 摘要；下载完成后校验，安装前还会核对包名、版本号及签名。

## 发布新版

1. 更新 `app/pubspec.yaml` 的版本，例如 `1.2.1+9`；版本名称和 build number 应递增。
2. 使用与当前安装版相同的签名密钥构建 APK，包名保持 `app.music163.music163_app`。当前本机测试签名要保持稳定；源码包不包含签名密钥。使用 CI 构建时也需要配置同一固定签名。
3. 在 GitHub 创建正式 Release，Tag 使用 `v1.2.1`，填写更新内容。
4. 上传通用 APK，推荐文件名 `Suishiting-1.2.1.apk`，等待上传完成后发布。可以同时上传源码 ZIP 与校验文件。应用只选择 APK。
5. 已安装应用进入「账号与设置 → 应用更新 → 检查更新」，下载并按系统提示安装。

普通版本使用 `v主版本.次版本.补丁版本`。仅提升构建号时也可使用 `v1.2.1+10`；推荐同时提升补丁版本以保持发布记录清晰。Draft 与 Prerelease 不向稳定版用户提供。

GitHub 上传安装包后会提供资产摘要 `digest: sha256:...`，不需要另写更新 JSON。摘要尚不可用时，应用会提示等待发布者重新上传。

同一 Release 有多个 APK 时优先选择上述标准文件名，其次选择文件名包含 `universal` 的包。推荐每个正式版本只提供一个通用 APK；源码 ZIP 不受影响。

## 更改更新源

构建时可指定公开仓库：

```sh
flutter build apk --release --dart-define=SUISHITING_UPDATE_REPOSITORY=owner/repository
```

检查更新不需要 GitHub Token，也不发送音乐账号 Cookie。首次安装更新由用户在 Android 系统界面授权，应用不会自动更改系统权限或静默安装。

## 验证范围

版本比较、Release 解析、摘要/大小校验、跳转限制、取消下载和权限状态有自动化测试。原生安装通道已随 APK 编译；手机上下载并安装未来版本，需要在首次正式 Release 发布后做设备验收。
