cmake_minimum_required(VERSION 3.1)
set(CMAKE_CXX_STANDARD 11)

project(mtlx-to-osl)

if (NOT IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/MaterialX/source")
message(FATAL_ERROR "mtlx-to-osl depends on MaterialX.
    git submodule update --init --recursive")
endif()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/MaterialX)

add_executable(mtlx-to-osl source/main.cpp)

target_link_libraries(
        mtlx-to-osl
        MaterialXCore
        MaterialXFormat
        MaterialXGenOsl
        MaterialXGenShader
        MaterialXRender)
