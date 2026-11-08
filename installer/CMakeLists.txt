# Versión mínima de CMake requerida (Buena práctica)
cmake_minimum_required(VERSION 3.10)

# Nombre del proyecto y lenguajes (C para glad.c, CXX para el lanzador)
project(NebulaLauncher LANGUAGES C CXX)

# Definir el estándar de C++
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_definitions(_CRT_SECURE_NO_WARNINGS)

# Buscar paquete estándar de OpenGL y Threads
set(OpenGL_GL_PREFERENCE GLVND)
find_package(OpenGL REQUIRED)
find_package(Threads REQUIRED)
include(FetchContent)

# 1. GLFW (Ventanas y contexto OpenGL)
FetchContent_Declare(
    glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG        3.5.1
)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(glfw)

# 2. Dear ImGui (Rama docking)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/vendor/imgui/imgui.cpp")
    set(IMGUI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/imgui")
    set(IMGUI_BACKENDS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/imgui/backends")
else()
    FetchContent_Declare(
        imgui
        GIT_REPOSITORY https://github.com/ocornut/imgui.git
        GIT_TAG        docking
    )
    FetchContent_GetProperties(imgui)
    if(NOT imgui_POPULATED)
        FetchContent_Populate(imgui)
    endif()
    set(IMGUI_DIR "${imgui_SOURCE_DIR}")
    set(IMGUI_BACKENDS_DIR "${imgui_SOURCE_DIR}/backends")
endif()

add_library(imgui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_BACKENDS_DIR}/imgui_impl_glfw.cpp
    ${IMGUI_BACKENDS_DIR}/imgui_impl_opengl3.cpp
)

target_include_directories(imgui PUBLIC
    ${IMGUI_DIR}
    ${IMGUI_BACKENDS_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor/glad/include
)

target_link_libraries(imgui PUBLIC
    glfw
    OpenGL::GL
)

add_executable(NebulaLauncher 
    src/main.cpp
    src/glad.c
    src/installer/installerGui.cpp
    src/downloader.cpp
    src/launcher_core.cpp
    src/stb_image_impl.cpp
)

# Agregar el directorio include y vendor a las rutas de búsqueda de headers
target_include_directories(NebulaLauncher PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/vendor
)

# Enlazar ImGui (esto hereda automáticamente GLFW, OpenGL y vendor/glad/include por ser PUBLIC)
target_link_libraries(NebulaLauncher PRIVATE
    imgui
)

if(WIN32)
    target_link_libraries(NebulaLauncher PRIVATE winhttp ole32 shell32 dwmapi)
    # Hide the console window on Windows GUI
    set_target_properties(NebulaLauncher PROPERTIES WIN32_EXECUTABLE TRUE)
    if(MSVC)
        target_link_options(NebulaLauncher PRIVATE "/ENTRY:mainCRTStartup")
    endif()
else()
    find_package(CURL REQUIRED)
    target_link_libraries(NebulaLauncher PRIVATE CURL::libcurl Threads::Threads)
endif()