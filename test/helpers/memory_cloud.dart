import 'package:my_manager/sync/cloud_store.dart';
import 'package:my_manager/sync/google_auth.dart';

/// «Google Drive» у пам'яті: спільний для кількох імітованих пристроїв.
class MemoryCloudStore implements CloudStore {
  final files = <String, String>{};
  var writes = 0;
  bool offline = false;

  @override
  Future<String?> read(String name) async {
    if (offline) throw const CloudException('offline');
    return files[name];
  }

  @override
  Future<void> write(String name, String content) async {
    if (offline) throw const CloudException('offline');
    writes++;
    files[name] = content;
  }
}

/// Вхід без Google: одразу «успішний».
class FakeSyncAuth implements SyncAuth {
  FakeSyncAuth({this.configured = true, this.email = 'me@example.com'});
  final bool configured;
  final String email;
  var signInCalls = 0;
  var interactiveCalls = 0;

  /// false — імітує прострочений дозвіл (режим Testing, 7 днів).
  bool authorized = true;

  @override
  bool get isConfigured => configured;

  @override
  Future<String> signIn() async {
    signInCalls++;
    return email;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> accessToken({String? invalidToken}) async => authorized ? 'fake-token' : null;

  @override
  Future<void> authorizeInteractive() async {
    interactiveCalls++;
    authorized = true;
  }
}
