cmake_minimum_required(VERSION 3.20)
project(SpektraLabRawTests LANGUAGES CXX)

set(SPEKTRALAB_SOURCE_DIR "" CACHE PATH "Pinned SpektraLab checkout")
set(engine "${SPEKTRALAB_SOURCE_DIR}/engine")
if(NOT EXISTS "${engine}/cmake/LibRaw.cmake")
    message(FATAL_ERROR "Set SPEKTRALAB_SOURCE_DIR to the pinned checkout")
endif()

find_package(Threads REQUIRED)
find_package(JPEG REQUIRED)
include("${engine}/cmake/LibRaw.cmake")
target_compile_definitions(spk_libraw PUBLIC USE_JPEG USE_X3FTOOLS)
target_link_libraries(spk_libraw PUBLIC JPEG::JPEG)

add_executable(test_raw_worker
    ../test-raw-worker.cpp
    ../../native/raw_decode.cpp
    "${engine}/src/io/raw_decoder.cpp"
    "${engine}/src/io/raw_headroom.cpp"
)
target_compile_features(test_raw_worker PRIVATE cxx_std_20)
target_include_directories(test_raw_worker PRIVATE "${engine}/src")
target_link_libraries(test_raw_worker PRIVATE spk_libraw Threads::Threads)
