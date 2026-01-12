#ifndef FLUTTER_PLUGIN_OPUS_FLUTTER_WINDOWS_NONE_H_
#define FLUTTER_PLUGIN_OPUS_FLUTTER_WINDOWS_NONE_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

FLUTTER_PLUGIN_EXPORT void noneRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

#endif  // FLUTTER_PLUGIN_OPUS_FLUTTER_WINDOWS_NONE_H_
