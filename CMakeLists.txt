cmake_minimum_required(VERSION 3.1)
set(CMAKE_CXX_STANDARD 11)

project(mtlx-to-osl)

if (NOT IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/MaterialX/source")
message(FATAL_ERROR "mtlx-to-osl depends on MaterialX.
    git submodule update --init --recursive")
endif()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/MaterialX)

file(GLOB source "${CMAKE_CURRENT_SOURCE_DIR}/source/*.cpp")
file(GLOB headers "${CMAKE_CURRENT_SOURCE_DIR}/source/*.h*")
add_executable(mtlx-to-osl ${source} ${headers})

target_link_libraries(
        mtlx-to-osl
        MaterialXCore
        MaterialXFormat
        MaterialXGenShader
        MaterialXGenOsl
        MaterialXGenGlsl
        MaterialXRender)
