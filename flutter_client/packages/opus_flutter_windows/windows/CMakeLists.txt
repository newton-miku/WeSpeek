cmake_minimum_required(VERSION 3.10)
project(opus_flutter_windows_plugin LANGUAGES CXX)

add_library(opus_flutter_windows_plugin SHARED
  "opus_flutter_windows_plugin.cpp"
)

target_compile_definitions(opus_flutter_windows_plugin PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(opus_flutter_windows_plugin INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(opus_flutter_windows_plugin PRIVATE flutter flutter_wrapper_plugin)

set_target_properties(opus_flutter_windows_plugin PROPERTIES
  OUTPUT_NAME "opus_flutter_windows_plugin"
)
