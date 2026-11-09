cmake_minimum_required(VERSION 3.20)
project(SpektraLabHarmony LANGUAGES C CXX)
set(SPEKTRALAB_SOURCE_DIR "" CACHE PATH "SpektraLab 445e314 source")
if(NOT EXISTS "${SPEKTRALAB_SOURCE_DIR}/engine/include/spektrafilm/spk_engine.h")
    message(FATAL_ERROR "Provide SPEKTRALAB_SOURCE_DIR")
endif()
set(BUILD_TESTING OFF)
set(SPEKTRALAB_REQUIRE_VULKAN ON CACHE BOOL "")
add_subdirectory("${SPEKTRALAB_SOURCE_DIR}/engine" engine)
set(SPEKTRALAB_JPEG_SOURCE "" CACHE PATH "Verified libjpeg-turbo 3.2.1 source")
if(NOT EXISTS "${SPEKTRALAB_JPEG_SOURCE}/src/jpeglib.h")
    message(FATAL_ERROR "Run scripts/setup-jpeg.sh and set SPEKTRALAB_JPEG_SOURCE")
endif()
include(ExternalProject)
ExternalProject_Add(harmony_jpeg_build
    SOURCE_DIR "${SPEKTRALAB_JPEG_SOURCE}"
    BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/jpeg"
    CMAKE_ARGS -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE} -DOHOS_ARCH=${OHOS_ARCH}
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF
    BUILD_COMMAND "${CMAKE_COMMAND}" --build <BINARY_DIR> --target jpeg-static
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS "${CMAKE_CURRENT_BINARY_DIR}/jpeg/libjpeg.a")
add_library(harmony_jpeg STATIC IMPORTED)
set_target_properties(harmony_jpeg PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/jpeg/libjpeg.a")
add_dependencies(harmony_jpeg harmony_jpeg_build)
target_compile_definitions(spk_libraw PUBLIC USE_JPEG USE_X3FTOOLS)
target_include_directories(spk_libraw PRIVATE "${SPEKTRALAB_JPEG_SOURCE}/src" "${CMAKE_CURRENT_BINARY_DIR}/jpeg")
target_link_libraries(spk_libraw PUBLIC harmony_jpeg)
add_executable(spektra_render_fixture "${SPEKTRALAB_SOURCE_DIR}/engine/tests/render_fixture.cpp")
target_compile_features(spektra_render_fixture PRIVATE cxx_std_20)
target_link_libraries(spektra_render_fixture PRIVATE spektralab_engine)
target_include_directories(spektra_render_fixture PRIVATE "${SPEKTRALAB_SOURCE_DIR}/engine/include")

add_library(spektralab SHARED editor_module.cpp raw_decode.cpp)
target_compile_features(spektralab PRIVATE cxx_std_20)
target_include_directories(spektralab PRIVATE "${SPEKTRALAB_SOURCE_DIR}/engine/include")
target_link_libraries(spektralab PRIVATE spektralab_engine spk_image_io spk_libraw libace_napi.z.so)

# Apply the mobile dispatch policy to a build-tree copy of the pinned backend.
set(backend "${SPEKTRALAB_SOURCE_DIR}/engine/src/gpu/vulkan_gpu.cpp")
set(display_patch "${CMAKE_CURRENT_SOURCE_DIR}/vulkan-display.patch")
set(mobile_backend "${CMAKE_CURRENT_BINARY_DIR}/vulkan_gpu.cpp")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${backend}" "${display_patch}")
execute_process(COMMAND patch -s -o "${mobile_backend}" -i "${display_patch}" "${backend}"
    COMMAND_ERROR_IS_FATAL ANY)
get_target_property(engine_sources spektralab_engine SOURCES)
list(REMOVE_ITEM engine_sources src/gpu/vulkan_gpu.cpp)
set_property(TARGET spektralab_engine PROPERTY SOURCES ${engine_sources} "${mobile_backend}")
target_include_directories(spektralab_engine PRIVATE "${SPEKTRALAB_SOURCE_DIR}/engine/src/gpu")
