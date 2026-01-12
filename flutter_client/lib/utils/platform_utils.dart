import 'platform/platform_adapter.dart';
import 'platform/desktop_adapter.dart'
    if (dart.library.html) 'platform/web_adapter.dart';

final PlatformAdapter platformAdapter = createAdapter();
