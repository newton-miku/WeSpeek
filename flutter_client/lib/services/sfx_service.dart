import 'sfx_service_stub.dart'
    if (dart.library.js_interop) 'sfx_service_web.dart'
    if (dart.library.io) 'sfx_service_native.dart';

abstract class SfxService {
  static SfxService? _instance;
  static SfxService get instance => _instance ??= createSfxService();

  Future<void> init();
  Future<void> playJoin();
  Future<void> playLeave();
  Future<void> playWarning();
  Future<void> playSuccess();
  void dispose();
}
