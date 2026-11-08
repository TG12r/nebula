#include <installerGui.hpp>
#include <logo_data.hpp>
#include <stb_image.h>

#include <cmath>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#ifdef APIENTRY
#undef APIENTRY
#endif
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>
#endif

namespace NebulaLauncher {

static std::string formatBytes(size_t bytes) {
  if (bytes == 0)
    return "0 B";
  double d = static_cast<double>(bytes);
  if (d < 1024.0)
    return std::to_string(bytes) + " B";
  d /= 1024.0;
  if (d < 1024.0) {
    std::stringstream ss;
    ss << std::fixed << std::setprecision(1) << d << " KB";
    return ss.str();
  }
  d /= 1024.0;
  std::stringstream ss;
  ss << std::fixed << std::setprecision(1) << d << " MB";
  return ss.str();
}

installerGui::installerGui() {
  setInstallDir(LauncherCore::getSavedInstallDir());
}

void installerGui::setInstallDir(const std::string &newDir) {
  if (newDir.empty())
    return;

  std::string normalized;
  std::string err;
  if (!LauncherCore::validateAndNormalizePath(newDir, normalized, err)) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pathValidationError = err;
    return;
  }

  {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pathValidationError.clear();
    m_installDir = normalized;
    std::strncpy(m_installDirBuffer, normalized.c_str(),
                 sizeof(m_installDirBuffer) - 1);
    m_installDirBuffer[sizeof(m_installDirBuffer) - 1] = '\0';
  }
  LauncherCore::saveInstallDir(normalized);
  std::string curVer = LauncherCore::getInstalledVersion(normalized);
  bool isInstalled = LauncherCore::isAppInstalled(normalized);

  {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_currentVersion = curVer;
    if (isInstalled) {
      m_lastInstalledDir = normalized;
    }
  }

#ifdef _WIN32
  // Cleanup any temporary leftover from a previous launcher self-update
  std::error_code ec;
  std::filesystem::path oldLauncher =
      std::filesystem::path(normalized) / "NebulaLauncher.exe.old";
  if (std::filesystem::exists(oldLauncher)) {
    std::filesystem::remove(oldLauncher, ec);
  }
#endif
}

void installerGui::startMigrateInstallation(const std::string &fromDir,
                                            const std::string &toDir) {
  if (m_workerThread.joinable()) {
    m_workerThread.join();
  }

  m_state = GuiState::EXTRACTING;
  m_statusTitle = "Moviendo instalacion...";
  m_statusDetail = "Copiando archivos de forma segura a la nueva ubicacion...";

  m_workerThread = std::thread([this, fromDir, toDir]() {
    std::string err;
    bool ok = LauncherCore::migrateInstallation(fromDir, toDir, err);
    if (!ok) {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::ERROR_STATE;
      m_statusTitle = "Error al mover instalacion";
      m_statusDetail = err;
      m_errorMessage = err;
      return;
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    m_lastInstalledDir = toDir;
    m_currentVersion = LauncherCore::getInstalledVersion(toDir);
    m_state = GuiState::UP_TO_DATE;
    m_statusTitle = "Instalacion movida con exito (v" + m_currentVersion + ")";
    m_statusDetail = "Iniciando Nebula...";
    triggerLaunch();
  });
}

void *installerGui::getNativeWindowHandle() {
#ifdef _WIN32
  if (m_window) {
    return static_cast<void *>(glfwGetWin32Window(m_window));
  }
#endif
  return nullptr;
}

#ifdef _WIN32
void installerGui::initTaskbar() {
  HWND hwnd = static_cast<HWND>(getNativeWindowHandle());
  if (hwnd) {
    ITaskbarList3* tbl = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, IID_ITaskbarList3, reinterpret_cast<void**>(&tbl));
    if (SUCCEEDED(hr) && tbl) {
      tbl->HrInit();
      m_taskbarList = static_cast<void*>(tbl);
    }
  }
}

void installerGui::setTaskbarProgress(size_t completed, size_t total) {
  if (!m_taskbarList) return;
  HWND hwnd = static_cast<HWND>(getNativeWindowHandle());
  if (!hwnd) return;
  ITaskbarList3* tbl = static_cast<ITaskbarList3*>(m_taskbarList);
  tbl->SetProgressState(hwnd, TBPF_NORMAL);
  tbl->SetProgressValue(hwnd, completed, total);
}

void installerGui::setTaskbarState(int state) {
  if (!m_taskbarList) return;
  HWND hwnd = static_cast<HWND>(getNativeWindowHandle());
  if (!hwnd) return;
  ITaskbarList3* tbl = static_cast<ITaskbarList3*>(m_taskbarList);
  switch (state) {
    case 0: tbl->SetProgressState(hwnd, TBPF_NOPROGRESS); break;
    case 1: tbl->SetProgressState(hwnd, TBPF_INDETERMINATE); break;
    case 2: tbl->SetProgressState(hwnd, TBPF_NORMAL); break;
    case 3: tbl->SetProgressState(hwnd, TBPF_ERROR); break;
    default: tbl->SetProgressState(hwnd, TBPF_NOPROGRESS); break;
  }
}
#endif

installerGui::~installerGui() {
  m_cancelRequested = true;
  if (m_workerThread.joinable()) {
    m_workerThread.join();
  }
#ifdef _WIN32
  if (m_taskbarList) {
    HWND hwnd = static_cast<HWND>(getNativeWindowHandle());
    if (hwnd) {
      static_cast<ITaskbarList3*>(m_taskbarList)->SetProgressState(hwnd, TBPF_NOPROGRESS);
    }
    static_cast<ITaskbarList3*>(m_taskbarList)->Release();
    m_taskbarList = nullptr;
  }
#endif
  if (m_logoTexture != 0) {
    glDeleteTextures(1, &m_logoTexture);
    m_logoTexture = 0;
  }
}

void installerGui::applyTheme() {
  ImGuiStyle &style = ImGui::GetStyle();
  style.WindowRounding = 12.0f;
  style.ChildRounding = 10.0f;
  style.FrameRounding = 8.0f;
  style.PopupRounding = 8.0f;
  style.ScrollbarRounding = 8.0f;
  style.GrabRounding = 6.0f;
  style.TabRounding = 8.0f;

  style.WindowBorderSize = 1.0f;
  style.FrameBorderSize = 1.0f;
  style.PopupBorderSize = 1.0f;

  style.WindowPadding = ImVec2(24.0f, 20.0f);
  style.FramePadding = ImVec2(14.0f, 8.0f);
  style.ItemSpacing = ImVec2(10.0f, 10.0f);
  style.ItemInnerSpacing = ImVec2(8.0f, 6.0f);

  ImVec4 *colors = style.Colors;
  // Nebula Deep Obsidian Palette (Matches AppTheme cmfBlack & cmfDarkGrey)
  colors[ImGuiCol_WindowBg] = ImVec4(0.038f, 0.035f, 0.062f, 1.00f); // #0A0910
  colors[ImGuiCol_ChildBg] = ImVec4(0.078f, 0.068f, 0.125f, 0.85f);  // #141120
  colors[ImGuiCol_PopupBg] = ImVec4(0.070f, 0.063f, 0.110f, 0.98f);
  colors[ImGuiCol_Border] =
      ImVec4(0.240f, 0.180f, 0.360f, 0.50f); // #3D2E5C (Cosmic Violet border)
  colors[ImGuiCol_BorderShadow] = ImVec4(0.000f, 0.000f, 0.000f, 0.00f);

  colors[ImGuiCol_FrameBg] = ImVec4(0.106f, 0.090f, 0.160f, 1.00f); // #1B1729
  colors[ImGuiCol_FrameBgHovered] = ImVec4(0.155f, 0.130f, 0.230f, 1.00f);
  colors[ImGuiCol_FrameBgActive] = ImVec4(0.200f, 0.165f, 0.290f, 1.00f);

  colors[ImGuiCol_TitleBg] = ImVec4(0.038f, 0.035f, 0.062f, 1.00f);
  colors[ImGuiCol_TitleBgActive] = ImVec4(0.038f, 0.035f, 0.062f, 1.00f);
  colors[ImGuiCol_TitleBgCollapsed] = ImVec4(0.038f, 0.035f, 0.062f, 1.00f);

  // Nebula Purple Signature Accent (#8A2BE2 / Color(0xFF8A2BE2))
  colors[ImGuiCol_Button] = ImVec4(0.541f, 0.169f, 0.886f, 0.90f); // #8A2BE2
  colors[ImGuiCol_ButtonHovered] =
      ImVec4(0.635f, 0.282f, 0.945f, 1.00f); // #A248F1
  colors[ImGuiCol_ButtonActive] =
      ImVec4(0.447f, 0.118f, 0.745f, 1.00f); // #721EBE

  colors[ImGuiCol_Text] =
      ImVec4(0.961f, 0.957f, 0.980f, 1.00f); // cmfWhite / #F5F4FA
  colors[ImGuiCol_TextDisabled] = ImVec4(0.480f, 0.440f, 0.580f, 1.00f);

  colors[ImGuiCol_CheckMark] = ImVec4(0.720f, 0.400f, 0.980f, 1.00f);
  colors[ImGuiCol_SliderGrab] = ImVec4(0.541f, 0.169f, 0.886f, 1.00f);
  colors[ImGuiCol_SliderGrabActive] = ImVec4(0.720f, 0.400f, 0.980f, 1.00f);

  colors[ImGuiCol_ScrollbarBg] = ImVec4(0.038f, 0.035f, 0.062f, 0.60f);
  colors[ImGuiCol_ScrollbarGrab] = ImVec4(0.240f, 0.180f, 0.360f, 0.70f);
  colors[ImGuiCol_ScrollbarGrabHovered] = ImVec4(0.320f, 0.240f, 0.480f, 0.90f);
  colors[ImGuiCol_ScrollbarGrabActive] = ImVec4(0.541f, 0.169f, 0.886f, 1.00f);

  colors[ImGuiCol_PlotHistogram] =
      ImVec4(0.541f, 0.169f, 0.886f, 1.00f); // Nebula Purple fill
  colors[ImGuiCol_PlotHistogramHovered] = ImVec4(0.635f, 0.282f, 0.945f, 1.00f);

  colors[ImGuiCol_Header] = ImVec4(0.180f, 0.140f, 0.260f, 0.80f);
  colors[ImGuiCol_HeaderHovered] = ImVec4(0.240f, 0.180f, 0.360f, 0.90f);
  colors[ImGuiCol_HeaderActive] = ImVec4(0.320f, 0.240f, 0.480f, 1.00f);
}

bool installerGui::loadLogoTexture() {
  int channels = 0;
  unsigned char *data =
      stbi_load_from_memory(NEBULA_LOGO_PNG, (int)NEBULA_LOGO_PNG_LEN,
                            &m_logoWidth, &m_logoHeight, &channels, 4);

  if (!data) {
    return false;
  }

  glGenTextures(1, &m_logoTexture);
  glBindTexture(GL_TEXTURE_2D, m_logoTexture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_logoWidth, m_logoHeight, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, data);

  stbi_image_free(data);
  return true;
}

void installerGui::initGui(GLFWwindow *window, int monitorX, int monitorY,
                           int screenW, int screenH, int splashW, int splashH,
                           int expandedW, int expandedH) {
  m_window = window;
  m_monitorX = monitorX;
  m_monitorY = monitorY;
  m_screenW = screenW;
  m_screenH = screenH;
  m_splashW = splashW;
  m_splashH = splashH;
  m_expandedW = expandedW;
  m_expandedH = expandedH;
  m_currentW = static_cast<float>(splashW);
  m_currentH = static_cast<float>(splashH);
  m_isExpanded = false;
  m_expandProgress = 0.0f;

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO &io = ImGui::GetIO();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
  io.IniFilename = nullptr; // Don't create imgui.ini

  // Escalar fuentes y controles de acuerdo a la resolucion de la pantalla
  float uiScale = static_cast<float>(screenH) / 1080.0f;
  io.FontGlobalScale = std::clamp(uiScale, 0.9f, 2.0f);

  applyTheme();
  ImGui::GetStyle().ScaleAllSizes(std::clamp(uiScale, 0.85f, 2.0f));

  ImGui_ImplGlfw_InitForOpenGL(window, true);
  ImGui_ImplOpenGL3_Init("#version 130");

  loadLogoTexture();
  m_currentVersion = LauncherCore::getInstalledVersion(m_installDir);
  if (LauncherCore::isAppInstalled(m_installDir)) {
    m_lastInstalledDir = m_installDir;
  }

#ifdef _WIN32
  initTaskbar();
#endif

  startCheckUpdates(false);
}

void installerGui::startCheckUpdates(bool forceRefresh) {
  if (m_workerThread.joinable()) {
    m_workerThread.join();
  }

  m_state = GuiState::CHECKING_UPDATES;
  m_statusTitle = "Buscando actualizaciones...";
  m_statusDetail = "Conectando con GitHub (TG12r/nebula)...";

  m_workerThread = std::thread([this, forceRefresh]() {
    LauncherCore::ConfigData cfg = LauncherCore::loadConfig();
    int64_t now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();

    bool installed = LauncherCore::isAppInstalled(m_installDir);

    // Fast path: if not forced, app is installed, checked in the last hour, and we have cached release info
    if (!forceRefresh && installed && (now - cfg.lastCheckTimestamp < 3600) && !cfg.lastReleaseVersion.empty()) {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_latestRelease.tag = cfg.lastReleaseTag;
      m_latestRelease.version = cfg.lastReleaseVersion;
      m_latestRelease.assetName = cfg.lastAssetName;
      m_latestRelease.downloadUrl = cfg.lastDownloadUrl;
      m_latestRelease.assetSize = cfg.lastAssetSize;

      if (Downloader::isNewerVersion(cfg.lastReleaseVersion, m_currentVersion)) {
        m_state = GuiState::UPDATE_AVAILABLE;
        m_statusTitle = "¡Actualizacion disponible: v" + cfg.lastReleaseVersion + "!";
        m_statusDetail = "Version actual: v" + m_currentVersion + "  ->  Nueva: v" + cfg.lastReleaseVersion;
        m_isExpanded = true;
      } else {
        m_state = GuiState::UP_TO_DATE;
        m_statusTitle = "Iniciando Nebula...";
        m_statusDetail = "Tienes la version mas reciente: v" + m_currentVersion;
        triggerLaunch();
      }
      return;
    }

    ReleaseInfo rel;
    std::string err;
    bool ok = Downloader::fetchLatestRelease(rel, err);

    std::lock_guard<std::mutex> lock(m_mutex);
    if (!ok) {
      // If offline or GitHub error/rate-limit, check if local app is installed
      if (LauncherCore::isAppInstalled(m_installDir)) {
        m_state = GuiState::UP_TO_DATE;
        m_statusTitle = "Iniciando Nebula...";
        m_statusDetail = "Modo sin conexion: v" + m_currentVersion;

        triggerLaunch();
      } else {
        m_state = GuiState::ERROR_STATE;
        m_statusTitle = "Error de conexion";
        m_statusDetail = "No se pudo verificar actualizaciones: " + err;
        m_errorMessage = err;
        m_isExpanded = true;
      }
      return;
    }

    // Save successful check to cache
    cfg.lastCheckTimestamp = now;
    cfg.lastReleaseTag = rel.tag;
    cfg.lastReleaseVersion = rel.version;
    cfg.lastAssetName = rel.assetName;
    cfg.lastDownloadUrl = rel.downloadUrl;
    cfg.lastAssetSize = rel.assetSize;
    LauncherCore::saveConfig(cfg);

    m_latestRelease = rel;

    if (!installed) {
      m_state = GuiState::NOT_INSTALLED;
      m_statusTitle = "Instalar Nebula v" + rel.version;
      m_statusDetail = "Nebula aun no esta instalado en este equipo.";
      m_isExpanded = true; // Expand window to full installer card!
    } else if (Downloader::isNewerVersion(rel.version, m_currentVersion)) {
      m_state = GuiState::UPDATE_AVAILABLE;
      m_statusTitle = "¡Actualizacion disponible: v" + rel.version + "!";
      m_statusDetail = "Version actual: v" + m_currentVersion +
                       "  ->  Nueva: v" + rel.version;
      m_isExpanded = true; // Expand window to full updater card!
    } else {
      m_state = GuiState::UP_TO_DATE;
      m_statusTitle = "Iniciando Nebula...";
      m_statusDetail = "Tienes la version mas reciente: v" + m_currentVersion;
      // Launch immediately with ZERO waiting time!
      triggerLaunch();
    }
  });
}

void installerGui::startDownloadAndInstall() {
  if (m_workerThread.joinable()) {
    m_workerThread.join();
  }

  m_state = GuiState::DOWNLOADING;
  m_statusTitle = "Descargando Nebula v" + m_latestRelease.version + "...";
  m_statusDetail = "Preparando descarga...";
  m_downloadProgress = 0.0f;
  m_downloadedBytes = 0;
  m_totalBytes = m_latestRelease.assetSize;
  m_cancelRequested = false;

  m_workerThread = std::thread([this]() {
    std::string tempZip = m_installDir + "/nebula_update_temp.zip";
    std::string err;

    auto progressCb = [this](size_t dl, size_t total) {
      m_downloadedBytes = dl;
      m_totalBytes = total;
      if (total > 0) {
        m_downloadProgress = static_cast<float>(dl) / static_cast<float>(total);
#ifdef _WIN32
        setTaskbarProgress(dl, total);
#endif
      }
    };

    bool ok = Downloader::downloadFile(m_latestRelease.downloadUrl, tempZip,
                                       progressCb, m_cancelRequested, err);

    if (!ok) {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::ERROR_STATE;
      m_statusTitle = "Error en la descarga";
      m_statusDetail = err;
      m_errorMessage = err;
#ifdef _WIN32
      setTaskbarState(3); // Error
#endif
      return;
    }

    {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::EXTRACTING;
      m_statusTitle = "Instalando archivos...";
      m_statusDetail = "Descomprimiendo archivos portables de Nebula...";
#ifdef _WIN32
      setTaskbarState(1); // Indeterminate
#endif
    }

    ok = LauncherCore::extractReleaseZipSafe(tempZip, m_installDir, err);
    std::remove(tempZip.c_str());

    if (!ok) {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::ERROR_STATE;
      m_statusTitle = "Error al instalar archivos";
      m_statusDetail = err;
      m_errorMessage = err;
#ifdef _WIN32
      setTaskbarState(3); // Error
#endif
      return;
    }

    {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::CONFIGURING;
      m_statusTitle = "Configurando accesos directos...";
      m_statusDetail = "Integrando con el sistema y guardando configuracion...";
    }

    LauncherCore::installShortcuts(m_installDir, err);
    LauncherCore::setInstalledVersion(m_installDir, m_latestRelease.version);
    m_currentVersion = m_latestRelease.version;
    m_lastInstalledDir = m_installDir;

    // Register in Windows "Apps & Features" (Uninstall)
    std::string regErr;
    LauncherCore::registerUninstallEntry(m_installDir, m_latestRelease.version, regErr);

    {
      std::lock_guard<std::mutex> lock(m_mutex);
      m_state = GuiState::LAUNCHING;
      m_statusTitle = "¡Instalacion completada!";
      m_statusDetail = "Iniciando Nebula...";
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(800));
    triggerLaunch();
  });
}

void installerGui::triggerLaunch() {
#ifdef _WIN32
  setTaskbarState(0); // NoProgress
#endif
  std::string err;
  if (LauncherCore::launchApp(m_installDir, err)) {
    if (m_window) {
      glfwSetWindowShouldClose(m_window, GLFW_TRUE);
    }
  } else {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_state = GuiState::ERROR_STATE;
    m_statusTitle = "Error al iniciar";
    m_statusDetail = err;
    m_errorMessage = err;
#ifdef _WIN32
    setTaskbarState(3); // Error
#endif
  }
}

void installerGui::updateWindowAnimation() {
  if (!m_window)
    return;

  if (m_isExpanded && m_expandProgress < 1.0f) {
    float dt = ImGui::GetIO().DeltaTime;
    m_expandProgress = std::min(1.0f, m_expandProgress + dt * 4.0f);

    // Curva suave cubic ease-out
    float t = m_expandProgress;
    float ease = 1.0f - std::pow(1.0f - t, 3.0f);

    float targetW = static_cast<float>(m_expandedW);
    float targetH = static_cast<float>(m_expandedH);
    float startW = static_cast<float>(m_splashW);
    float startH = static_cast<float>(m_splashH);

    m_currentW = startW + (targetW - startW) * ease;
    m_currentH = startH + (targetH - startH) * ease;

    // Mantener centrado perfecto relativo a la pantalla del usuario en cada
    // frame
    int posX = m_monitorX + (m_screenW - static_cast<int>(m_currentW)) / 2;
    int posY = m_monitorY + (m_screenH - static_cast<int>(m_currentH)) / 2;

    glfwSetWindowSize(m_window, static_cast<int>(m_currentW),
                      static_cast<int>(m_currentH));
    glfwSetWindowPos(m_window, posX, posY);
  }
}

void installerGui::renderSplash(const ImVec2 &windowSize) {
  // Zona arrastrable en toda la ventana Splash excepto boton de cierre
  ImVec2 mousePos = ImGui::GetMousePos();
  bool mouseClicked = ImGui::IsMouseClicked(ImGuiMouseButton_Left);
  bool inCloseZone =
      (mousePos.x >= windowSize.x - 36.0f && mousePos.y <= 36.0f);

  if (mouseClicked && !inCloseZone) {
    m_windowDragging = true;
#ifdef _WIN32
    POINT pt;
    GetCursorPos(&pt);
    int winX = 0, winY = 0;
    glfwGetWindowPos(m_window, &winX, &winY);
    m_dragOffsetX = pt.x - winX;
    m_dragOffsetY = pt.y - winY;
#else
    double curX = 0.0, curY = 0.0;
    glfwGetCursorPos(m_window, &curX, &curY);
    m_dragOffsetX = static_cast<int>(curX);
    m_dragOffsetY = static_cast<int>(curY);
#endif
  }

  if (m_windowDragging) {
#ifdef _WIN32
    bool isDown = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    if (isDown) {
      POINT pt;
      GetCursorPos(&pt);
      int newWinX = pt.x - m_dragOffsetX;
      int newWinY = pt.y - m_dragOffsetY;
      int curWinX = 0, curWinY = 0;
      glfwGetWindowPos(m_window, &curWinX, &curWinY);
      if (newWinX != curWinX || newWinY != curWinY) {
        glfwSetWindowPos(m_window, newWinX, newWinY);
      }
    } else {
      m_windowDragging = false;
    }
#else
    if (ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
      int winX = 0, winY = 0;
      double curX = 0.0, curY = 0.0;
      glfwGetWindowPos(m_window, &winX, &winY);
      glfwGetCursorPos(m_window, &curX, &curY);
      int screenX = winX + static_cast<int>(curX);
      int screenY = winY + static_cast<int>(curY);
      glfwSetWindowPos(m_window, screenX - m_dragOffsetX,
                       screenY - m_dragOffsetY);
    } else {
      m_windowDragging = false;
    }
#endif
  }

  // Boton discreto para cerrar en modo Splash (arriba a la derecha)
  float closeBtnSize = 22.0f;
  ImGui::SetCursorPos(ImVec2(windowSize.x - closeBtnSize - 10.0f, 10.0f));
  ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                        ImVec4(0.85f, 0.20f, 0.25f, 0.9f));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive,
                        ImVec4(0.70f, 0.15f, 0.20f, 1.0f));
  ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(0, 0));
  if (ImGui::Button("X##splash_close", ImVec2(closeBtnSize, closeBtnSize))) {
    m_cancelRequested = true;
    glfwSetWindowShouldClose(m_window, GLFW_TRUE);
  }
  ImGui::PopStyleVar();
  ImGui::PopStyleColor(3);

  // Logo Nebula con pulsacion sutil estilo Discord
  float time = static_cast<float>(ImGui::GetTime());
  float pulse = 1.0f + 0.035f * sinf(time * 3.5f);
  float baseLogo = windowSize.y * 0.35f;
  float logoSize = baseLogo * pulse;
  float logoX = (windowSize.x - logoSize) * 0.5f;
  float logoY = windowSize.y * 0.16f;

  ImGui::SetCursorPos(ImVec2(logoX, logoY));
  if (m_logoTexture != 0) {
    ImGui::Image((ImTextureID)(intptr_t)m_logoTexture,
                 ImVec2(logoSize, logoSize));
  } else {
    ImGui::Dummy(ImVec2(logoSize, logoSize));
  }

  // Texto de estado centrado
  std::string text;
  {
    std::lock_guard<std::mutex> lock(m_mutex);
    text = m_statusTitle.empty() ? "Buscando actualizaciones..." : m_statusTitle;
  }
  float textW = ImGui::CalcTextSize(text.c_str()).x;
  ImGui::SetCursorPos(
      ImVec2((windowSize.x - textW) * 0.5f, windowSize.y * 0.60f));
  ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.85f, 0.72f, 1.0f, 1.0f));
  ImGui::Text("%s", text.c_str());
  ImGui::PopStyleColor();

  // Barra shimmer minimalista en la parte inferior
  float barW = windowSize.x * 0.74f;
  float barH = std::max(6.0f, windowSize.y * 0.035f);
  ImGui::SetCursorPos(
      ImVec2((windowSize.x - barW) * 0.5f, windowSize.y * 0.78f));
  float shimmer = (sinf(time * 4.0f) + 1.0f) * 0.5f;
  ImGui::ProgressBar(shimmer, ImVec2(barW, barH), "");
}

void installerGui::renderHeader(const ImVec2 &windowSize) {
  // Window dragging logic across the header bar
  ImVec2 mousePos = ImGui::GetMousePos();
  bool mouseClicked = ImGui::IsMouseClicked(ImGuiMouseButton_Left);

  // Draggable zone: top header bar (48px height), except the top-right control
  // buttons
  bool inHeaderZone =
      (mousePos.y >= 0.0f && mousePos.y <= 48.0f && mousePos.x >= 0.0f &&
       mousePos.x < (windowSize.x - 90.0f));

  if (mouseClicked && inHeaderZone) {
    m_windowDragging = true;
#ifdef _WIN32
    POINT pt;
    GetCursorPos(&pt);
    int winX = 0, winY = 0;
    glfwGetWindowPos(m_window, &winX, &winY);
    m_dragOffsetX = pt.x - winX;
    m_dragOffsetY = pt.y - winY;
#else
    double curX = 0.0, curY = 0.0;
    glfwGetCursorPos(m_window, &curX, &curY);
    m_dragOffsetX = static_cast<int>(curX);
    m_dragOffsetY = static_cast<int>(curY);
#endif
  }

  if (m_windowDragging) {
#ifdef _WIN32
    bool isDown = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    if (isDown) {
      POINT pt;
      GetCursorPos(&pt);
      int newWinX = pt.x - m_dragOffsetX;
      int newWinY = pt.y - m_dragOffsetY;
      int curWinX = 0, curWinY = 0;
      glfwGetWindowPos(m_window, &curWinX, &curWinY);
      if (newWinX != curWinX || newWinY != curWinY) {
        glfwSetWindowPos(m_window, newWinX, newWinY);
      }
    } else {
      m_windowDragging = false;
    }
#else
    if (ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
      int winX = 0, winY = 0;
      double curX = 0.0, curY = 0.0;
      glfwGetWindowPos(m_window, &winX, &winY);
      glfwGetCursorPos(m_window, &curX, &curY);
      int screenX = winX + static_cast<int>(curX);
      int screenY = winY + static_cast<int>(curY);
      glfwSetWindowPos(m_window, screenX - m_dragOffsetX,
                       screenY - m_dragOffsetY);
    } else {
      m_windowDragging = false;
    }
#endif
  }

  // Mini icon and title
  if (m_logoTexture != 0) {
    ImGui::Image((ImTextureID)(intptr_t)m_logoTexture, ImVec2(20, 20));
    ImGui::SameLine();
  }
  ImGui::TextColored(ImVec4(0.60f, 0.65f, 0.80f, 1.0f), "NEBULA LAUNCHER");

  // Right-aligned window controls
  float btnWidth = 32.0f;
  float btnHeight = 26.0f;
  float startX = windowSize.x - (btnWidth * 2.0f + 20.0f);

  ImGui::SameLine(startX);
  ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                        ImVec4(0.2f, 0.25f, 0.35f, 0.7f));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.15f, 0.2f, 0.3f, 0.9f));
  ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(0, 0));

  if (ImGui::Button("_##min", ImVec2(btnWidth, btnHeight))) {
    glfwIconifyWindow(m_window);
  }

  ImGui::SameLine();
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                        ImVec4(0.85f, 0.20f, 0.25f, 0.9f));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive,
                        ImVec4(0.70f, 0.15f, 0.20f, 1.0f));

  if (ImGui::Button("X##close", ImVec2(btnWidth, btnHeight))) {
    m_cancelRequested = true;
    glfwSetWindowShouldClose(m_window, GLFW_TRUE);
  }

  ImGui::PopStyleColor(5);
  ImGui::PopStyleVar();

  ImGui::Separator();
  ImGui::Spacing();
}

void installerGui::renderPathSelector(float availWidth) {
  ImGui::SetCursorPosX(16.5f);
  ImGui::TextColored(ImVec4(0.72f, 0.68f, 0.82f, 1.0f), "Carpeta de instalacion:");
  ImGui::Spacing();

  ImGui::SetCursorPosX(16.0f);
  float spacing = 8.0f;
  float btnBrowseW = 96.0f;
  float btnResetW = 108.0f;
  float totalRowW = availWidth - 32.0f;
  float inputW = totalRowW - btnBrowseW - btnResetW - (spacing * 2.0f);

  ImGui::PushItemWidth(inputW);
  if (ImGui::InputText("##InstallPath", m_installDirBuffer,
                       sizeof(m_installDirBuffer),
                       ImGuiInputTextFlags_EnterReturnsTrue)) {
    setInstallDir(m_installDirBuffer);
  }
  ImGui::PopItemWidth();

  // Style secondary buttons in dark cosmic violet
  ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                        ImVec4(0.250f, 0.190f, 0.380f, 1.00f));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive,
                        ImVec4(0.320f, 0.230f, 0.480f, 1.00f));

  ImGui::SameLine(0.0f, spacing);
  if (ImGui::Button("Examinar...##Browse", ImVec2(btnBrowseW, 0.0f))) {
    std::string chosen =
        LauncherCore::pickFolderDialog(getNativeWindowHandle());
    if (!chosen.empty()) {
      setInstallDir(chosen);
      bool installed = LauncherCore::isAppInstalled(m_installDir);
      if (!installed) {
        m_state = GuiState::NOT_INSTALLED;
        m_statusTitle = "Instalar Nebula v" + m_latestRelease.version;
        m_statusDetail = "Nebula se instalara en la ruta seleccionada.";
      } else if (Downloader::isNewerVersion(m_latestRelease.version,
                                            m_currentVersion)) {
        m_state = GuiState::UPDATE_AVAILABLE;
        m_statusTitle = "¡Actualizacion disponible: v" + m_latestRelease.version + "!";
        m_statusDetail = "Version actual: v" + m_currentVersion + "  ->  Nueva: v" + m_latestRelease.version;
      } else {
        m_state = GuiState::UP_TO_DATE;
        m_statusTitle = "Nebula esta al dia (v" + m_currentVersion + ")";
        m_statusDetail = "Tienes la version mas reciente instalada.";
      }
    }
  }

  ImGui::SameLine(0.0f, spacing);
  if (ImGui::Button("Por defecto##Default", ImVec2(btnResetW, 0.0f))) {
    setInstallDir(LauncherCore::getDefaultInstallDir());
    bool installed = LauncherCore::isAppInstalled(m_installDir);
    if (!installed) {
      m_state = GuiState::NOT_INSTALLED;
      m_statusTitle = "Instalar Nebula v" + m_latestRelease.version;
      m_statusDetail = "Nebula se instalara en la ruta seleccionada.";
    }
  }

  ImGui::PopStyleColor(3);

  if (!m_pathValidationError.empty()) {
    ImGui::SetCursorPosX(16.0f);
    ImGui::TextColored(ImVec4(0.95f, 0.35f, 0.35f, 1.0f), "%s", m_pathValidationError.c_str());
  }
}

void installerGui::renderFooter(const ImVec2 &windowSize) {
  ImGui::SetCursorPosY(windowSize.y - 44.0f);
  ImGui::Separator();
  ImGui::Spacing();

  ImGui::SetCursorPosX(24.0f);
  ImGui::TextColored(ImVec4(0.55f, 0.50f, 0.65f, 1.0f), "GitHub: TG12r/nebula");

  const char *btnLabel = "Abrir carpeta instalacion";
  float textW = ImGui::CalcTextSize(btnLabel).x;
  float btnW = textW + ImGui::GetStyle().FramePadding.x * 2.0f + 4.0f;
  float rightMargin = 24.0f;
  float targetX = windowSize.x - btnW - rightMargin;

  ImGui::SameLine(targetX);
  ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.70f));
  ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.250f, 0.190f, 0.380f, 0.90f));
  ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.320f, 0.230f, 0.480f, 1.00f));
  if (ImGui::SmallButton(btnLabel)) {
    std::string curDir;
    {
      std::lock_guard<std::mutex> lock(m_mutex);
      curDir = m_installDir;
    }
#ifdef _WIN32
    ShellExecuteA(NULL, "open", curDir.c_str(), NULL, NULL, SW_SHOWNORMAL);
#else
    std::string cmd = "xdg-open \"" + curDir + "\" &";
    if (std::system(cmd.c_str()) != 0) { /* ignored */
    }
#endif
  }
  ImGui::PopStyleColor(3);
}

void installerGui::renderExpanded(const ImVec2 &windowSize) {
  renderHeader(windowSize);

  // Center Hero: Logo & Title proporcionales
  float availWidth = ImGui::GetContentRegionAvail().x;
  float logoSize = std::clamp(windowSize.y * 0.17f, 56.0f, 130.0f);
  float logoX = (availWidth - logoSize) * 0.5f;

  ImGui::SetCursorPosX(ImGui::GetCursorPosX() + logoX);
  if (m_logoTexture != 0) {
    ImGui::Image((ImTextureID)(intptr_t)m_logoTexture, ImVec2(logoSize, logoSize));
  } else {
    ImGui::Dummy(ImVec2(logoSize, logoSize));
  }

  // Title centered
  std::string titleText = "N E B U L A";
  float titleWidth = ImGui::CalcTextSize(titleText.c_str()).x;
  ImGui::SetCursorPosX((availWidth - titleWidth) * 0.5f);
  ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.720f, 0.400f, 0.980f, 1.0f)); // Nebula Purple glow (#B866FA)
  ImGui::Text("%s", titleText.c_str());
  ImGui::PopStyleColor();

  // Subtitle centered
  std::string subText = "Reproductor de Musica en Streaming";
  float subWidth = ImGui::CalcTextSize(subText.c_str()).x;
  ImGui::SetCursorPosX((availWidth - subWidth) * 0.5f);
  ImGui::TextColored(ImVec4(0.60f, 0.56f, 0.72f, 1.0f), "%s", subText.c_str());

  ImGui::Spacing();

  // State Machine Container Card proporcional a la ventana
  float cardHeight = std::clamp(windowSize.y * 0.44f, 180.0f, 340.0f);
  ImVec2 cardSize(availWidth, cardHeight);
  ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.078f, 0.068f, 0.125f, 0.85f));
  ImGui::BeginChild("ActionCard", cardSize, true, ImGuiWindowFlags_NoScrollbar);

  std::lock_guard<std::mutex> lock(m_mutex);

  // Titulo y detalle del estado actual con flujo vertical limpio
  ImGui::SetCursorPosX(16.0f);
  ImGui::SetCursorPosY(14.0f);
  ImGui::TextColored(ImVec4(0.96f, 0.96f, 0.98f, 1.0f), "%s", m_statusTitle.c_str());

  ImGui::SetCursorPosX(16.0f);
  ImGui::TextColored(ImVec4(0.58f, 0.54f, 0.70f, 1.0f), "%s", m_statusDetail.c_str());
  ImGui::Spacing();
  ImGui::Spacing();

  float actionBtnWidth = std::clamp(cardSize.x * 0.36f, 170.0f, 280.0f);
  float actionBtnHeight = std::clamp(cardHeight * 0.20f, 32.0f, 46.0f);
  float btnY = cardSize.y - actionBtnHeight - 16.0f;

  switch (m_state) {
  case GuiState::CHECKING_UPDATES: {
    float time = static_cast<float>(ImGui::GetTime());
    float anim = (sinf(time * 3.5f) + 1.0f) * 0.5f;
    ImGui::SetCursorPosY(btnY);
    ImGui::SetCursorPosX(16.0f);
    ImGui::ProgressBar(
        anim, ImVec2(cardSize.x - 32.0f, 10.0f),
        "");
    break;
  }

  case GuiState::NOT_INSTALLED: {
    renderPathSelector(cardSize.x);

    bool canMigrate =
        (!m_lastInstalledDir.empty() && m_lastInstalledDir != m_installDir && LauncherCore::isAppInstalled(m_lastInstalledDir));

    ImGui::SetCursorPosY(btnY);
    if (canMigrate) {
      float migrateBtnW = actionBtnWidth * 1.15f;
      float totalW = migrateBtnW + actionBtnWidth + 12.0f;
      ImGui::SetCursorPosX((cardSize.x - totalW) * 0.5f);
      ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.541f, 0.169f, 0.886f, 0.95f));
      ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.635f, 0.282f, 0.945f, 1.00f));
      ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.447f, 0.118f, 0.745f, 1.00f));
      if (ImGui::Button("MOVER INSTALACION", ImVec2(migrateBtnW, actionBtnHeight))) {
        startMigrateInstallation(m_lastInstalledDir, m_installDir);
      }
      ImGui::PopStyleColor(3);

      ImGui::SameLine(0.0f, 12.0f);
      ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
      ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.250f, 0.190f, 0.380f, 1.00f));
      ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.320f, 0.230f, 0.480f, 1.00f));
      if (ImGui::Button("Instalar desde cero", ImVec2(actionBtnWidth, actionBtnHeight))) {
        startDownloadAndInstall();
      }
      ImGui::PopStyleColor(3);
    } else {
      ImGui::SetCursorPosX((cardSize.x - actionBtnWidth) * 0.5f);
      ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.541f, 0.169f, 0.886f, 0.95f));
      ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.635f, 0.282f, 0.945f, 1.00f));
      ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.447f, 0.118f, 0.745f, 1.00f));
      if (ImGui::Button("INSTALAR NEBULA", ImVec2(actionBtnWidth, actionBtnHeight))) {
        startDownloadAndInstall();
      }
      ImGui::PopStyleColor(3);
    }
    break;
  }

  case GuiState::UPDATE_AVAILABLE: {
    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(std::max(40.0f, cardHeight * 0.28f));
    std::string sizeStr = formatBytes(m_latestRelease.assetSize);
    ImGui::TextColored(ImVec4(0.720f, 0.400f, 0.980f, 1.0f), "Tamano: %s  •  Paquete: %s", sizeStr.c_str(), m_latestRelease.assetName.c_str());

    ImGui::SetCursorPosX(24.0f);
    ImGui::SetCursorPosY(std::max(85.0f, cardHeight * 0.58f));
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.541f, 0.169f, 0.886f, 0.95f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.635f, 0.282f, 0.945f, 1.00f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.447f, 0.118f, 0.745f, 1.00f));
    if (ImGui::Button("ACTUALIZAR AHORA", ImVec2(actionBtnWidth, actionBtnHeight))) {
      startDownloadAndInstall();
    }
    ImGui::PopStyleColor(3);

    ImGui::SameLine();
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.250f, 0.190f, 0.380f, 1.00f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.320f, 0.230f, 0.480f, 1.00f));
    if (ImGui::Button("Omitir y Abrir Actual",
                      ImVec2(actionBtnWidth, actionBtnHeight))) {
      triggerLaunch();
    }
    ImGui::PopStyleColor(3);
    break;
  }

  case GuiState::UP_TO_DATE: {
    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(std::max(40.0f, cardHeight * 0.28f));
    ImGui::TextColored(ImVec4(0.35f, 0.90f, 0.65f, 1.0f),
                       "Nebula esta listo para ejecutarse.");

    ImGui::SetCursorPosX(24.0f);
    ImGui::SetCursorPosY(std::max(85.0f, cardHeight * 0.58f));
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.541f, 0.169f, 0.886f, 0.95f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.635f, 0.282f, 0.945f, 1.00f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.447f, 0.118f, 0.745f, 1.00f));
    if (ImGui::Button("INICIAR NEBULA",
                      ImVec2(actionBtnWidth, actionBtnHeight))) {
      triggerLaunch();
    }
    ImGui::PopStyleColor(3);

    ImGui::SameLine();
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.250f, 0.190f, 0.380f, 1.00f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.320f, 0.230f, 0.480f, 1.00f));
    if (ImGui::Button("Reinstalar / Reparar", ImVec2(actionBtnWidth, actionBtnHeight))) {
      startDownloadAndInstall();
    }
    ImGui::PopStyleColor(3);
    break;
  }

  case GuiState::DOWNLOADING: {
    float frac = m_downloadProgress.load();
    size_t dl = m_downloadedBytes.load();
    size_t tot = m_totalBytes.load();

    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(std::max(36.0f, cardHeight * 0.22f));
    std::string progStr = formatBytes(dl) + " de " + formatBytes(tot);
    ImGui::TextColored(ImVec4(0.720f, 0.400f, 0.980f, 1.0f), "%s (%.0f%%)", progStr.c_str(), frac * 100.0f);

    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(std::max(68.0f, cardHeight * 0.50f));
    float cancelBtnW = std::clamp(cardSize.x * 0.22f, 80.0f, 130.0f);
    ImGui::ProgressBar(frac, ImVec2(cardSize.x - cancelBtnW - 36.0f, 14.0f), "");

    ImGui::SameLine();
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.70f, 0.18f, 0.25f, 0.90f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.55f, 0.12f, 0.18f, 1.00f));
    if (ImGui::Button("Cancelar", ImVec2(cancelBtnW, 28.0f))) {
      m_cancelRequested = true;
    }
    ImGui::PopStyleColor(3);
    break;
  }

  case GuiState::EXTRACTING:
  case GuiState::CONFIGURING:
  case GuiState::LAUNCHING: {
    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(cardHeight * 0.45f);
    float time = static_cast<float>(ImGui::GetTime());
    float anim = (sinf(time * 4.0f) + 1.0f) * 0.5f;
    ImGui::ProgressBar(anim, ImVec2(cardSize.x - 32.0f, 12.0f), "");
    break;
  }

  case GuiState::ERROR_STATE: {
    ImGui::SetCursorPosX(16.0f);
    ImGui::SetCursorPosY(std::max(36.0f, cardHeight * 0.22f));
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.95f, 0.35f, 0.35f, 1.0f));
    ImGui::TextWrapped("%s", m_errorMessage.c_str());
    ImGui::PopStyleColor();

    ImGui::SetCursorPosX(24.0f);
    ImGui::SetCursorPosY(std::max(85.0f, cardHeight * 0.60f));
    ImGui::PushStyleColor(ImGuiCol_Button,
                          ImVec4(0.541f, 0.169f, 0.886f, 0.95f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                          ImVec4(0.635f, 0.282f, 0.945f, 1.00f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive,
                          ImVec4(0.447f, 0.118f, 0.745f, 1.00f));
    if (ImGui::Button("Reintentar", ImVec2(actionBtnWidth * 0.8f, actionBtnHeight))) {
      startCheckUpdates(true);
    }
    ImGui::PopStyleColor(3);

    if (LauncherCore::isAppInstalled(m_installDir)) {
      ImGui::SameLine();
      ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.160f, 0.130f, 0.230f, 0.85f));
      ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.250f, 0.190f, 0.380f, 1.00f));
      ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.320f, 0.230f, 0.480f, 1.00f));
      if (ImGui::Button("Abrir version local", ImVec2(actionBtnWidth, actionBtnHeight))) {
        triggerLaunch();
      }
      ImGui::PopStyleColor(3);
    }
    break;
  }
  }

  ImGui::EndChild();
  ImGui::PopStyleColor();

  renderFooter(windowSize);
}

void installerGui::update(ImVec2 &windowSize) {
  updateWindowAnimation();
  windowSize = ImVec2(m_currentW, m_currentH);

  ImGuiWindowFlags flags =
      ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
      ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar |
      ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoBringToFrontOnFocus;

  ImGui::SetNextWindowSize(windowSize);
  ImGui::SetNextWindowPos(ImVec2(0, 0));

  ImGui::Begin("NebulaLauncherRoot", nullptr, flags);

  if (!m_isExpanded && m_expandProgress == 0.0f) {
    renderSplash(windowSize);
  } else {
    renderExpanded(windowSize);
  }

  ImGui::End();
}

} // namespace NebulaLauncher