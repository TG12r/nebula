#if defined(_WIN32)
#pragma comment(linker, "/SUBSYSTEM:windows /ENTRY:mainCRTStartup")
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <dwmapi.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#endif

#include <cstdio>
#include <string>
#include <algorithm>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#if defined(_WIN32)
#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>
#endif

#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <installerGui.hpp>
#include <launcher_core.hpp>
#include <logo_data.hpp>
#include <stb_image.h>

int main(int argc, char* argv[]) {
#if defined(_WIN32)
    FreeConsole();
    HWND consoleWnd = GetConsoleWindow();
    if (consoleWnd != nullptr) {
        ShowWindow(consoleWnd, SW_HIDE);
    }
#endif

    // Manejo de parametro de desinstalacion
    bool isUninstall = false;
    bool isSilent = false;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--uninstall") isUninstall = true;
        if (arg == "--silent" || arg == "-s") isSilent = true;
    }

    if (isUninstall) {
        std::string installDir = NebulaLauncher::LauncherCore::getSavedInstallDir();
        if (!isSilent) {
#if defined(_WIN32)
            int choice = MessageBoxW(
                NULL,
                L"¿Estas seguro de que deseas desinstalar Nebula y eliminar todos sus componentes?",
                L"Desinstalar Nebula",
                MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2
            );
            if (choice != IDYES) {
                return 0;
            }
#endif
        }
        std::string err;
        bool ok = NebulaLauncher::LauncherCore::uninstallApp(installDir, err);
        if (!isSilent) {
#if defined(_WIN32)
            if (ok) {
                MessageBoxW(NULL, L"Nebula se ha desinstalado correctamente de tu equipo.", L"Desinstalacion completada", MB_OK | MB_ICONINFORMATION);
            } else {
                std::wstring wErr = L"Hubo un error durante la desinstalacion: " + NebulaLauncher::toWide(err);
                MessageBoxW(NULL, wErr.c_str(), L"Error", MB_OK | MB_ICONERROR);
            }
#endif
        }
        return ok ? 0 : 1;
    }

#if defined(_WIN32)
    // Instancia Unica en Windows via Named Mutex
    HANDLE hSingleInstanceMutex = CreateMutexW(NULL, TRUE, L"NebulaLauncherSingleInstanceMutex");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND existingWnd = FindWindowW(NULL, L"Nebula Launcher");
        if (existingWnd) {
            ShowWindow(existingWnd, SW_RESTORE);
            SetForegroundWindow(existingWnd);
        }
        if (hSingleInstanceMutex) {
            CloseHandle(hSingleInstanceMutex);
        }
        return 0;
    }

    // Inicializacion centralizada del subsistema COM
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
#else
    int lockFd = open("/tmp/nebula_launcher.lock", O_CREAT | O_RDWR, 0666);
    if (lockFd >= 0 && flock(lockFd, LOCK_EX | LOCK_NB) != 0) {
        close(lockFd);
        return 0;
    }
#endif

    // Inicialización de GLFW
    if (!glfwInit()) {
        printf("Failed to initialize GLFW\n");
#if defined(_WIN32)
        CoUninitialize();
        if (hSingleInstanceMutex) {
            ReleaseMutex(hSingleInstanceMutex);
            CloseHandle(hSingleInstanceMutex);
        }
#endif
        return -1;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
    glfwWindowHint(GLFW_DECORATED, GLFW_FALSE);
    
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();	
    const GLFWvidmode* mode = glfwGetVideoMode(monitor);
    int monitorX = 0, monitorY = 0;
    if (monitor) {
        glfwGetMonitorPos(monitor, &monitorX, &monitorY);
    }

    int screenW = mode ? mode->width : 1920;
    int screenH = mode ? mode->height : 1080;

    // Dimensiones proporcionales a la pantalla del monitor del usuario:
    // Splash inicial: ~20% de ancho, ~20% de alto (adaptable a 720p, 1080p, 2K, 4K)
    int splashW = std::max(320, static_cast<int>(screenW * 0.20f));
    int splashH = std::max(220, static_cast<int>(screenH * 0.20f));

    // Modo expandido: ~36% de ancho, ~44% de alto respecto a la pantalla
    int expandedW = std::max(560, static_cast<int>(screenW * 0.36f));
    int expandedH = std::max(420, static_cast<int>(screenH * 0.44f));

    ImVec2 windowSize = ImVec2(static_cast<float>(splashW), static_cast<float>(splashH));

    // Crear la ventana inicialmente en modo Splash
    GLFWwindow* window = glfwCreateWindow(splashW, splashH, "Nebula Launcher", nullptr, nullptr);
    if (window == nullptr) {
        printf("Failed to create GLFW window\n");
        glfwTerminate();
#if defined(_WIN32)
        CoUninitialize();
        if (hSingleInstanceMutex) {
            ReleaseMutex(hSingleInstanceMutex);
            CloseHandle(hSingleInstanceMutex);
        }
#endif
        return -1;
    }

#if defined(_WIN32)
    // Sombra suave nativa DWM para ventana sin bordes
    HWND hwnd = glfwGetWin32Window(window);
    if (hwnd != nullptr) {
        DWMNCRENDERINGPOLICY policy = DWMNCRP_ENABLED;
        DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY, &policy, sizeof(policy));
        MARGINS margins = { 1, 1, 1, 1 };
        DwmExtendFrameIntoClientArea(hwnd, &margins);
    }
#endif

    // Centrar la ventana en el monitor
    int initialX = monitorX + (screenW - splashW) / 2;
    int initialY = monitorY + (screenH - splashH) / 2;
    glfwSetWindowPos(window, initialX, initialY);

    // Establecer icono de la ventana (para la barra de tareas)
    {
        GLFWimage icon;
        int channels = 0;
        icon.pixels = stbi_load_from_memory(NEBULA_LOGO_PNG, (int)NEBULA_LOGO_PNG_LEN, &icon.width, &icon.height, &channels, 4);
        if (icon.pixels) {
            glfwSetWindowIcon(window, 1, &icon);
            stbi_image_free(icon.pixels);
        }
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1); // Enable V-Sync

    // Inicializar GLAD
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        printf("Failed to initialize GLAD\n");
        glfwDestroyWindow(window);
        glfwTerminate();
#if defined(_WIN32)
        CoUninitialize();
        if (hSingleInstanceMutex) {
            ReleaseMutex(hSingleInstanceMutex);
            CloseHandle(hSingleInstanceMutex);
        }
#endif
        return -1;
    }
  
    NebulaLauncher::installerGui gui;
    gui.initGui(window, monitorX, monitorY, screenW, screenH, splashW, splashH, expandedW, expandedH);

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        // Iniciar frame de ImGui
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        gui.update(windowSize);

        // Renderizado
        ImGui::Render();
        int display_w, display_h;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(0.038f, 0.035f, 0.062f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        glfwSwapBuffers(window);
    }

    // 7. Limpieza
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    glfwDestroyWindow(window);
    glfwTerminate();

#if defined(_WIN32)
    CoUninitialize();
    if (hSingleInstanceMutex) {
        ReleaseMutex(hSingleInstanceMutex);
        CloseHandle(hSingleInstanceMutex);
    }
#else
    if (lockFd >= 0) {
        flock(lockFd, LOCK_UN);
        close(lockFd);
    }
#endif
    return 0;
}