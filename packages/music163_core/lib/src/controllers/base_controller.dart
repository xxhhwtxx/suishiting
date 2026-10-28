import 'package:flutter/foundation.dart';
import '../domain/models.dart';

class SafeNotifier extends ChangeNotifier {
  bool closed = false;
  void changed() {
    if (!closed) notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

String userError(Object error) =>
    error is MusicException ? error.message : '操作未完成，请稍后重试。';
