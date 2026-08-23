cmake_minimum_required(VERSION 3.10)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "webkit_multi_view_plugin.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})
add_dependencies(${BINARY_NAME} flutter_assemble)
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  add_dependencies(${BINARY_NAME} flutter_assemble)
endif()

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WEBKIT2GTK)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

set_target_properties(${BINARY_NAME} PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH ${CMAKE_INSTALL_RPATH}
)
