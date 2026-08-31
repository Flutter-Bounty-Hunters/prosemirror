import 'package:prosemirror/src/dependencies/w3c_keyname/platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    as p;

/// Whether the current platform is macOS or iOS.
bool get isMacPlatform => p.isMacPlatform;

/// Whether the current platform is Windows.
bool get isWindowsPlatform => p.isWindowsPlatform;
