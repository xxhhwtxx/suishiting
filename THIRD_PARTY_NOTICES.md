# Source and dependency notices

Music163 Flutter is an independent Flutter adaptation created on 2026-10-28.
The Android app is branded 随时听 (Suishiting) from version 1.1.0.

QQ music search, track metadata, authorized vkey filenames, QQ OAuth QR flow,
and credential refresh protocol in `qq_api.dart` are independently implemented
in Dart with reference to L-1124/QQMusicApi (GPL-3.0-or-later), revision
`27861e51432ea6b6e88dc35c4e8c8e239c0339e8`:
https://github.com/L-1124/QQMusicApi . Authors and contributors retain their
copyright. No Python runtime or third-party API server is included.
EllanStudio/qqmusic-api was also inspected as a protocol comparison;
its Java implementation is not bundled in the app.

The NetEase EAPI wire format, request signing, endpoint paths and payload shapes
in `packages/music163_core/lib/src/data/netease_api.dart` and
`music_repository.dart` are ported from XiaoMengXinX/Music163Api-Go.
The repository/client flow is informed by XiaoMengXinX/Music163bot-Go v3.
Both original projects are credited to their respective authors and contributors.
The Go implementation was reimplemented in Dart; Telegram integration and Go runtime
are not included in the APK.

Original sources:

* https://github.com/XiaoMengXinX/Music163bot-Go
* https://github.com/XiaoMengXinX/Music163Api-Go

Source revisions inspected:

* Music163bot-Go: `0346e1aecfd57a031377ecc21f0f4e6a5b9c39af`
* Music163Api-Go: `9167996e9052ab8a0b3826f0614d5f5f0b092241`

This adaptation is distributed under GNU GPL version 3, in LICENSE. Source is
provided alongside the APK, including build instructions and dependency locks.

Flutter and the individual Dart/Android plugins retain their own licenses.
Flutter's generated application license registry includes their bundled notices.
Principal packages: http, crypto, pointycastle, just_audio, audio_session,
flutter_secure_storage, path_provider, path, and UI dependencies in app/pubspec.yaml.
Consult each package's LICENSE and pub.dev page for its exact license text.

No private account cookie, Telegram credential, or purchased service key is
included. The EAPI constant is a protocol constant, not a user account token.
