import 'package:prosemirror/src/commands/platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    as p;

/// Whether the current platform is macOS or iOS.
bool get isMacPlatform => p.isMacPlatform;
