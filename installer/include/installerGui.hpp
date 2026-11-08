#pragma once

#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <string>
#include <atomic>
#include <thread>
#include <mutex>
#include <chrono>

#include <downloader.hpp>
#include <launcher_core.hpp>

namespace NebulaLauncher {

enum class GuiState {
    CHECKING_UPDATES,
    NOT_INSTALLED,
    UPDATE_AVAILABLE,
    UP_TO_DATE,
    DOWNLOADING,
    EXTRACTING,
    CONFIGURING,
    LAUNCHING,
    ERROR_STATE
};

class installerGui {
public:
    installerGui();
    ~installerGui();

    void initGui(
        GLFWwindow* window,
        int monitorX = 0, int monitorY = 0,
        int screenW = 1920, int screenH = 1080,
        int splashW = 360, int splashH = 240,
        int expandedW = 640, int expandedH = 440
    );
    void update(ImVec2& windowSize);

private:
    void applyTheme();
    bool loadLogoTexture();
    void startCheckUpdates(bool forceRefresh = false);
    void startDownloadAndInstall();
    void triggerLaunch();
    void updateWindowAnimation();
    void renderSplash(const ImVec2& windowSize);
    void renderExpanded(const ImVec2& windowSize);
    void renderHeader(const ImVec2& windowSize);
    void renderFooter(const ImVec2& windowSize);
    void renderPathSelector(float availWidth);
    void setInstallDir(const std::string& newDir);
    void startMigrateInstallation(const std::string& fromDir, const std::string& toDir);
    void* getNativeWindowHandle();

#ifdef _WIN32
    void* m_taskbarList = nullptr;
    void initTaskbar();
    void setTaskbarProgress(size_t completed, size_t total);
    void setTaskbarState(int state); // 0: NoProgress, 1: Indeterminate, 2: Normal, 3: Error
#endif

    GLFWwindow* m_window = nullptr;
    GLuint m_logoTexture = 0;
    int m_logoWidth = 0;
    int m_logoHeight = 0;

    int m_monitorX = 0;
    int m_monitorY = 0;
    int m_screenW = 1920;
    int m_screenH = 1080;
    int m_splashW = 360;
    int m_splashH = 240;
    int m_expandedW = 640;
    int m_expandedH = 440;
    float m_currentW = 360.0f;
    float m_currentH = 240.0f;
    bool m_isExpanded = false;
    float m_expandProgress = 0.0f;

    std::string m_installDir;
    std::string m_lastInstalledDir;
    char m_installDirBuffer[512] = {0};
    std::string m_pathValidationError;
    std::string m_currentVersion;
    ReleaseInfo m_latestRelease;

    GuiState m_state = GuiState::CHECKING_UPDATES;
    std::string m_statusTitle;
    std::string m_statusDetail;
    std::string m_errorMessage;

    std::atomic<float> m_downloadProgress{0.0f};
    std::atomic<size_t> m_downloadedBytes{0};
    std::atomic<size_t> m_totalBytes{0};
    std::atomic<bool> m_cancelRequested{false};

    std::thread m_workerThread;
    std::mutex m_mutex;

    bool m_windowDragging = false;
    int m_dragOffsetX = 0;
    int m_dragOffsetY = 0;
};

} // namespace NebulaLauncher