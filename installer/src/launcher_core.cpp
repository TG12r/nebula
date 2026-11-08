#include <launcher_core.hpp>
#include <logo_data.hpp>
#include <nlohmann/json.hpp>

#include <iostream>
#include <fstream>
#include <sstream>
#include <filesystem>
#include <cstdlib>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <tlhelp32.h>
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")
#else
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <cstring>
#endif

namespace fs = std::filesystem;

namespace NebulaLauncher {

#ifdef _WIN32

std::wstring toWide(const std::string& str) {
    if (str.empty()) return L"";
    int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.length(), NULL, 0);
    std::wstring wstr(count, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.length(), &wstr[0], count);
    return wstr;
}

std::string toUtf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int count = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(), NULL, 0, NULL, NULL);
    std::string str(count, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(), &str[0], count, NULL, NULL);
    return str;
}

static bool createWindowsShortcut(
    const std::wstring& shortcutPath,
    const std::wstring& targetPath,
    const std::wstring& workingDir,
    const std::wstring& iconPath,
    const std::wstring& description
) {
    IShellLinkW* psl = NULL;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, IID_IShellLinkW, (void**)&psl);
    if (SUCCEEDED(hr)) {
        psl->SetPath(targetPath.c_str());
        psl->SetWorkingDirectory(workingDir.c_str());
        psl->SetDescription(description.c_str());
        if (!iconPath.empty()) {
            psl->SetIconLocation(iconPath.c_str(), 0);
        }

        IPersistFile* ppf = NULL;
        hr = psl->QueryInterface(IID_IPersistFile, (void**)&ppf);
        if (SUCCEEDED(hr)) {
            hr = ppf->Save(shortcutPath.c_str(), TRUE);
            ppf->Release();
        }
        psl->Release();
    }
    return SUCCEEDED(hr);
}

#endif

std::string LauncherCore::getCurrentExecutablePath() {
#ifdef _WIN32
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(NULL, path, MAX_PATH);
    return toUtf8(path);
#else
    char result[1024];
    ssize_t count = readlink("/proc/self/exe", result, sizeof(result) - 1);
    if (count > 0) {
        result[count] = '\0';
        return std::string(result, count);
    }
    return "";
#endif
}

std::string LauncherCore::getDefaultInstallDir() {
#ifdef _WIN32
    wchar_t localAppData[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, localAppData))) {
        fs::path p(localAppData);
        p /= "Nebula";
        return p.string();
    }
    const char* env = std::getenv("LOCALAPPDATA");
    if (env) {
        fs::path p(env);
        p /= "Nebula";
        return p.string();
    }
    return "C:\\Nebula";
#else
    const char* xdgData = std::getenv("XDG_DATA_HOME");
    if (xdgData && *xdgData) {
        fs::path p(xdgData);
        p /= "nebula";
        return p.string();
    }
    const char* home = std::getenv("HOME");
    if (home) {
        fs::path p(home);
        p /= ".local";
        p /= "share";
        p /= "nebula";
        return p.string();
    }
    return "/opt/nebula";
#endif
}

std::string LauncherCore::getAppDir(const std::string& installDir) {
    fs::path p(installDir);
    p /= "app";
    return p.string();
}

std::string LauncherCore::getAppExecutablePath(const std::string& installDir) {
    fs::path p = getAppDir(installDir);
#ifdef _WIN32
    p /= "nebula.exe";
#else
    p /= "nebula";
#endif
    return p.string();
}

std::string LauncherCore::getLauncherExecutablePath(const std::string& installDir) {
    fs::path p(installDir);
#ifdef _WIN32
    p /= "NebulaLauncher.exe";
#else
    p /= "NebulaLauncher";
#endif
    return p.string();
}

std::string LauncherCore::getVersionFilePath(const std::string& installDir) {
    fs::path p(installDir);
    p /= "installed_version.txt";
    return p.string();
}

bool LauncherCore::isAppInstalled(const std::string& installDir) {
    std::string exe = getAppExecutablePath(installDir);
    return fs::exists(exe);
}

std::string LauncherCore::getInstalledVersion(const std::string& installDir) {
    std::string vFile = getVersionFilePath(installDir);
    if (fs::exists(vFile)) {
        std::ifstream f(vFile);
        if (f.is_open()) {
            std::string ver;
            std::getline(f, ver);
            // Trim whitespace
            ver.erase(0, ver.find_first_not_of(" \t\r\n"));
            ver.erase(ver.find_last_not_of(" \t\r\n") + 1);
            if (!ver.empty()) return ver;
        }
    }

    if (isAppInstalled(installDir)) {
        return "1.2.0"; // default fallback for already installed app
    }
    return "";
}

bool LauncherCore::setInstalledVersion(const std::string& installDir, const std::string& version) {
    try {
        fs::create_directories(installDir);
        std::string vFile = getVersionFilePath(installDir);
        std::ofstream f(vFile, std::ios::trunc);
        if (f.is_open()) {
            f << version << std::endl;
            return true;
        }
    } catch (...) {}
    return false;
}

bool LauncherCore::extractReleaseZip(
    const std::string& zipPath,
    const std::string& targetAppDir,
    std::string& outError
) {
    try {
        fs::create_directories(targetAppDir);

        // Terminate any running nebula app before extraction
        fs::path tPath(targetAppDir);
        terminateRunningApp(tPath.parent_path().string());

#ifdef _WIN32
        // Run tar.exe with CREATE_NO_WINDOW so no black console window ever flashes
        std::wstring cmdW = toWide("tar.exe -xf \"" + zipPath + "\" -C \"" + targetAppDir + "\"");
        STARTUPINFOW si = { sizeof(si) };
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_HIDE;
        PROCESS_INFORMATION pi = { 0 };

        bool success = false;
        if (CreateProcessW(NULL, &cmdW[0], NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
            WaitForSingleObject(pi.hProcess, INFINITE);
            DWORD exitCode = 0;
            GetExitCodeProcess(pi.hProcess, &exitCode);
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            if (exitCode == 0) {
                success = true;
            }
        }

        if (!success) {
            // Fallback: PowerShell Expand-Archive silently
            std::wstring psCmdW = toWide("powershell.exe -WindowStyle Hidden -Command \"Expand-Archive -Path '" + zipPath + "' -DestinationPath '" + targetAppDir + "' -Force\"");
            STARTUPINFOW psi = { sizeof(psi) };
            psi.dwFlags = STARTF_USESHOWWINDOW;
            psi.wShowWindow = SW_HIDE;
            PROCESS_INFORMATION ppi = { 0 };
            if (CreateProcessW(NULL, &psCmdW[0], NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &psi, &ppi)) {
                WaitForSingleObject(ppi.hProcess, INFINITE);
                DWORD exitCode = 0;
                GetExitCodeProcess(ppi.hProcess, &exitCode);
                CloseHandle(ppi.hProcess);
                CloseHandle(ppi.hThread);
                if (exitCode == 0) {
                    success = true;
                }
            }
        }

        if (!success) {
            outError = "Fallo al descomprimir el archivo de instalacion";
            return false;
        }
#else
        // Linux: extract using unzip, bsdtar, python3 zipfile, or 7z
        std::string cmd = "unzip -q -o \"" + zipPath + "\" -d \"" + targetAppDir + "\" 2>/dev/null "
                          "|| bsdtar -xf \"" + zipPath + "\" -C \"" + targetAppDir + "\" 2>/dev/null "
                          "|| python3 -m zipfile -e \"" + zipPath + "\" \"" + targetAppDir + "\" 2>/dev/null "
                          "|| 7z x -y \"" + zipPath + "\" -o\"" + targetAppDir + "\" >/dev/null 2>&1";
        int res = std::system(cmd.c_str());
        if (res != 0) {
            outError = "Fallo al descomprimir el archivo en Linux (se requiere unzip, bsdtar o python3)";
            return false;
        }
#endif

        // Normalize layout if the release zip contains a wrapper folder ("windows", "linux", "bundle", "Release", etc.)
        std::vector<std::string> candidateFolders = {
#ifdef _WIN32
            "windows", "Release", "runner"
#else
            "linux", "bundle", "Release"
#endif
        };

        for (const auto& folder : candidateFolders) {
            fs::path subPath = fs::path(targetAppDir) / folder;
            if (fs::exists(subPath) && fs::is_directory(subPath)) {
                for (const auto& entry : fs::directory_iterator(subPath)) {
                    fs::path dest = fs::path(targetAppDir) / entry.path().filename();
                    if (fs::exists(dest)) {
                        fs::remove_all(dest);
                    }
                    fs::rename(entry.path(), dest);
                }
                fs::remove_all(subPath);
                break;
            }
        }

        // Fallback: check if the expected executable is located inside any single child directory
        std::string expectedBinName = 
#ifdef _WIN32
            "nebula.exe";
#else
            "nebula";
#endif
        if (!fs::exists(fs::path(targetAppDir) / expectedBinName)) {
            for (const auto& entry : fs::directory_iterator(targetAppDir)) {
                if (entry.is_directory() && fs::exists(entry.path() / expectedBinName)) {
                    for (const auto& subEntry : fs::directory_iterator(entry.path())) {
                        fs::path dest = fs::path(targetAppDir) / subEntry.path().filename();
                        if (fs::exists(dest)) {
                            fs::remove_all(dest);
                        }
                        fs::rename(subEntry.path(), dest);
                    }
                    fs::remove_all(entry.path());
                    break;
                }
            }
        }

#ifndef _WIN32
        // Ensure executable and read permissions on Linux binaries and shared libraries
        std::error_code permEc;
        for (const auto& entry : fs::recursive_directory_iterator(targetAppDir, permEc)) {
            if (entry.is_directory()) {
                chmod(entry.path().c_str(), 0755);
            } else if (entry.is_regular_file()) {
                std::string fname = entry.path().filename().string();
                std::string ext = entry.path().extension().string();
                if (fname == "nebula" || fname == "NebulaLauncher" || ext == ".so") {
                    chmod(entry.path().c_str(), 0755);
                } else {
                    chmod(entry.path().c_str(), 0644);
                }
            }
        }
#endif

        return true;
    } catch (const std::exception& e) {
        outError = std::string("Error durante la extraccion: ") + e.what();
        return false;
    }
}

bool LauncherCore::installShortcuts(const std::string& installDir, std::string& outError) {
    try {
        fs::create_directories(installDir);

        // 1. Save icon.png to installDir
        fs::path iconPath = fs::path(installDir) / "icon.png";
        {
            std::ofstream iconFile(iconPath.string(), std::ios::binary | std::ios::trunc);
            if (iconFile.is_open()) {
                iconFile.write(reinterpret_cast<const char*>(NEBULA_LOGO_PNG), NEBULA_LOGO_PNG_LEN);
            }
        }

        // 2. Copy current running NebulaLauncher to installDir if different
        std::string currentExe = getCurrentExecutablePath();
        std::string targetLauncherExe = getLauncherExecutablePath(installDir);
        if (!currentExe.empty() && fs::exists(currentExe)) {
            try {
                if (fs::canonical(currentExe) != fs::canonical(targetLauncherExe)) {
                    fs::copy_file(currentExe, targetLauncherExe, fs::copy_options::overwrite_existing);
                }
            } catch (...) {
                // If targetLauncherExe doesn't exist yet, copy directly
                if (!fs::exists(targetLauncherExe)) {
                    fs::copy_file(currentExe, targetLauncherExe, fs::copy_options::overwrite_existing);
                }
            }
#ifndef _WIN32
            if (fs::exists(targetLauncherExe)) {
                chmod(targetLauncherExe.c_str(), 0755);
            }
#endif
        }

#ifdef _WIN32
        std::wstring wLauncher = toWide(targetLauncherExe);
        std::wstring wInstallDir = toWide(installDir);
        std::string appExe = getAppExecutablePath(installDir);
        std::wstring wIcon = fs::exists(appExe) ? toWide(appExe) : toWide(iconPath.string());
        std::wstring wDesc = L"Nebula - Reproductor de Musica";

        // Create Desktop Shortcut
        wchar_t desktopPath[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_DESKTOPDIRECTORY, NULL, 0, desktopPath))) {
            fs::path dPath(desktopPath);
            dPath /= "Nebula.lnk";
            createWindowsShortcut(dPath.wstring(), wLauncher, wInstallDir, wIcon, wDesc);
        }

        // Create Start Menu Programs Shortcut
        wchar_t programsPath[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PROGRAMS, NULL, 0, programsPath))) {
            fs::path pPath(programsPath);
            pPath /= "Nebula.lnk";
            createWindowsShortcut(pPath.wstring(), wLauncher, wInstallDir, wIcon, wDesc);
        }

#else
        // Linux: create .desktop file in ~/.local/share/applications/nebula.desktop
        const char* home = std::getenv("HOME");
        if (home) {
            fs::path appsDir = fs::path(home) / ".local" / "share" / "applications";
            fs::create_directories(appsDir);
            fs::path desktopFile = appsDir / "nebula.desktop";

            std::ofstream df(desktopFile.string(), std::ios::trunc);
            if (df.is_open()) {
                df << "[Desktop Entry]\n";
                df << "Name=Nebula\n";
                df << "Comment=Reproductor de Musica en Streaming\n";
                df << "Exec=\"" << targetLauncherExe << "\"\n";
                df << "Icon=" << iconPath.string() << "\n";
                df << "Terminal=false\n";
                df << "Type=Application\n";
                df << "Categories=Audio;AudioVideo;Player;\n";
                df << "StartupWMClass=nebula\n";
            }
            chmod(desktopFile.string().c_str(), 0755);
        }
#endif

        return true;
    } catch (const std::exception& e) {
        outError = std::string("Error al crear accesos directos: ") + e.what();
        return false;
    }
}

bool LauncherCore::launchApp(const std::string& installDir, std::string& outError) {
    std::string exePath = getAppExecutablePath(installDir);
    if (!fs::exists(exePath)) {
        outError = "El ejecutable de Nebula no existe en: " + exePath;
        return false;
    }

    std::string appDir = getAppDir(installDir);

#ifdef _WIN32
    std::wstring wExe = toWide(exePath);
    std::wstring wDir = toWide(appDir);

    HINSTANCE res = ShellExecuteW(
        NULL,
        L"open",
        wExe.c_str(),
        NULL,
        wDir.c_str(),
        SW_SHOWNORMAL
    );

    if ((INT_PTR)res <= 32) {
        outError = "Fallo al iniciar el ejecutable (ShellExecute error " + std::to_string((INT_PTR)res) + ")";
        return false;
    }
    return true;
#else
    // 1. Ensure executable permissions on executable and bundled shared libraries
    chmod(exePath.c_str(), 0755);
    fs::path libDir = fs::path(appDir) / "lib";
    if (fs::exists(libDir)) {
        std::error_code ec;
        for (const auto& entry : fs::directory_iterator(libDir, ec)) {
            if (entry.is_regular_file()) {
                std::string ext = entry.path().extension().string();
                if (ext == ".so" || entry.path().string().find(".so.") != std::string::npos) {
                    chmod(entry.path().c_str(), 0755);
                }
            }
        }
    }

    // 2. Create pipe with FD_CLOEXEC to catch execv failures immediately
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        pipefd[0] = -1;
        pipefd[1] = -1;
    } else {
        fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);
        fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
    }

    pid_t pid = fork();
    if (pid == 0) {
        // Child process: create independent session so it outlives the launcher
        setsid();
        if (chdir(appDir.c_str()) != 0) {
            // continue even if chdir fails
        }

        // Configure LD_LIBRARY_PATH so bundled Flutter engine and plugins are always found
        if (fs::exists(libDir)) {
            const char* curLd = std::getenv("LD_LIBRARY_PATH");
            std::string newLd = libDir.string();
            if (curLd && *curLd) {
                newLd += ":" + std::string(curLd);
            }
            setenv("LD_LIBRARY_PATH", newLd.c_str(), 1);
        }

        // Redirect stdout & stderr to log file so launch crashes/errors are captured
        fs::path logFile = fs::path(installDir) / "nebula_app.log";
        int logFd = open(logFile.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (logFd != -1) {
            dup2(logFd, STDOUT_FILENO);
            dup2(logFd, STDERR_FILENO);
            close(logFd);
        }

        if (pipefd[0] != -1) close(pipefd[0]);

        char* args[] = { const_cast<char*>(exePath.c_str()), nullptr };
        execv(exePath.c_str(), args);

        // If execv failed, report error back to parent process
        int err = errno;
        if (pipefd[1] != -1) {
            ssize_t w = write(pipefd[1], &err, sizeof(err));
            (void)w;
            close(pipefd[1]);
        }
        _exit(127);
    } else if (pid < 0) {
        if (pipefd[0] != -1) close(pipefd[0]);
        if (pipefd[1] != -1) close(pipefd[1]);
        outError = "Fallo al iniciar Nebula en Linux (fork error: " + std::string(strerror(errno)) + ")";
        return false;
    }

    // Parent process: close write end
    if (pipefd[1] != -1) close(pipefd[1]);

    // Check if execv reported an immediate error
    if (pipefd[0] != -1) {
        int childErr = 0;
        struct pollfd pfd;
        pfd.fd = pipefd[0];
        pfd.events = POLLIN | POLLHUP;
        int pollRes = poll(&pfd, 1, 300);

        if (pollRes > 0) {
            ssize_t bytesRead = read(pipefd[0], &childErr, sizeof(childErr));
            if (bytesRead > 0 && childErr != 0) {
                close(pipefd[0]);
                outError = "Error al ejecutar Nebula: " + std::string(strerror(childErr));
                return false;
            }
        }
        close(pipefd[0]);
    }

    // Brief check (150ms) to see if process crashed on immediate startup
    usleep(150000);
    int status = 0;
    pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid && WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        fs::path logFile = fs::path(installDir) / "nebula_app.log";
        std::string logDetail = "";
        if (fs::exists(logFile)) {
            std::ifstream lf(logFile.string());
            std::string line;
            while (std::getline(lf, line)) {
                if (!line.empty()) logDetail = line;
            }
        }
        if (!logDetail.empty()) {
            outError = "Nebula se cerro al iniciar: " + logDetail;
        } else {
            outError = "Nebula se cerro inmediatamente con codigo " + std::to_string(WEXITSTATUS(status));
        }
        return false;
    }

    return true;
#endif
}

bool LauncherCore::isAppRunning(const std::string& installDir) {
#ifdef _WIN32
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W pe;
    pe.dwSize = sizeof(pe);

    std::string expectedExe = installDir.empty() ? "" : getAppExecutablePath(installDir);
    std::wstring wExpected = toWide(expectedExe);

    bool running = false;
    if (Process32FirstW(hSnap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, L"nebula.exe") == 0) {
                if (wExpected.empty()) {
                    running = true;
                    break;
                }
                HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
                if (hProc) {
                    wchar_t fullPath[MAX_PATH] = {0};
                    DWORD size = MAX_PATH;
                    if (QueryFullProcessImageNameW(hProc, 0, fullPath, &size)) {
                        if (_wcsicmp(fullPath, wExpected.c_str()) == 0) {
                            running = true;
                            CloseHandle(hProc);
                            break;
                        }
                    }
                    CloseHandle(hProc);
                }
            }
        } while (Process32NextW(hSnap, &pe));
    }
    CloseHandle(hSnap);
    return running;
#else
    (void)installDir;
    int res = std::system("pgrep -x nebula > /dev/null 2>&1 || pidof nebula > /dev/null 2>&1");
    return (res == 0);
#endif
}

bool LauncherCore::terminateRunningApp(const std::string& installDir) {
#ifdef _WIN32
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return false;

    PROCESSENTRY32W pe;
    pe.dwSize = sizeof(pe);

    std::string expectedExe = installDir.empty() ? "" : getAppExecutablePath(installDir);
    std::wstring wExpected = toWide(expectedExe);

    bool terminated = false;
    if (Process32FirstW(hSnap, &pe)) {
        do {
            if (_wcsicmp(pe.szExeFile, L"nebula.exe") == 0) {
                bool shouldKill = false;
                if (wExpected.empty()) {
                    shouldKill = true;
                } else {
                    HANDLE hProcQuery = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pe.th32ProcessID);
                    if (hProcQuery) {
                        wchar_t fullPath[MAX_PATH] = {0};
                        DWORD size = MAX_PATH;
                        if (QueryFullProcessImageNameW(hProcQuery, 0, fullPath, &size)) {
                            if (_wcsicmp(fullPath, wExpected.c_str()) == 0) {
                                shouldKill = true;
                            }
                        }
                        CloseHandle(hProcQuery);
                    }
                }

                if (shouldKill) {
                    HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                    if (hProc) {
                        TerminateProcess(hProc, 0);
                        CloseHandle(hProc);
                        terminated = true;
                    }
                }
            }
        } while (Process32NextW(hSnap, &pe));
    }
    CloseHandle(hSnap);
    if (terminated) {
        Sleep(500); // Give OS time to release file locks
    }
    return terminated;
#else
    (void)installDir;
    (void)std::system("pkill -x nebula 2>/dev/null || killall -q nebula 2>/dev/null");
    sleep(1);
    return true;
#endif
}

std::string LauncherCore::getConfigFilePath() {
#ifdef _WIN32
    wchar_t localAppData[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, localAppData))) {
        fs::path p(localAppData);
        p /= "Nebula";
        p /= "launcher_config.json";
        return p.string();
    }
    return "launcher_config.json";
#else
    const char* home = std::getenv("HOME");
    if (home) {
        fs::path p = fs::path(home) / ".config" / "nebula" / "launcher_config.json";
        return p.string();
    }
    return "launcher_config.json";
#endif
}

LauncherCore::ConfigData LauncherCore::loadConfig() {
    ConfigData cfg;
    cfg.installDir = getDefaultInstallDir();
    std::string cfgPath = getConfigFilePath();
    if (fs::exists(cfgPath)) {
        try {
            std::ifstream f(cfgPath);
            if (f.is_open()) {
                auto doc = nlohmann::json::parse(f);
                cfg.installDir = doc.value("install_dir", cfg.installDir);
                cfg.lastCheckTimestamp = doc.value("last_check_timestamp", (int64_t)0);
                cfg.lastReleaseTag = doc.value("last_release_tag", "");
                cfg.lastReleaseVersion = doc.value("last_release_version", "");
                cfg.lastAssetName = doc.value("last_asset_name", "");
                cfg.lastDownloadUrl = doc.value("last_download_url", "");
                cfg.lastAssetSize = doc.value("last_asset_size", (size_t)0);
            }
        } catch (...) {}
    }
    return cfg;
}

bool LauncherCore::saveConfig(const ConfigData& cfg) {
    std::string cfgPath = getConfigFilePath();
    try {
        fs::create_directories(fs::path(cfgPath).parent_path());
        nlohmann::json doc;
        doc["install_dir"] = cfg.installDir;
        doc["last_check_timestamp"] = cfg.lastCheckTimestamp;
        doc["last_release_tag"] = cfg.lastReleaseTag;
        doc["last_release_version"] = cfg.lastReleaseVersion;
        doc["last_asset_name"] = cfg.lastAssetName;
        doc["last_download_url"] = cfg.lastDownloadUrl;
        doc["last_asset_size"] = cfg.lastAssetSize;

        std::ofstream f(cfgPath, std::ios::trunc);
        if (f.is_open()) {
            f << doc.dump(4);
            return true;
        }
    } catch (...) {}
    return false;
}

std::string LauncherCore::getSavedInstallDir() {
    // 1. Check if launcher is located inside an existing installation folder
    std::string currentExe = getCurrentExecutablePath();
    if (!currentExe.empty()) {
        fs::path currentDir = fs::path(currentExe).parent_path();
        if (fs::exists(currentDir / "app" / "nebula.exe") || fs::exists(currentDir / "app" / "nebula")) {
            return currentDir.string();
        }
    }

    // 2. Check saved config file
    ConfigData cfg = loadConfig();
    if (!cfg.installDir.empty()) {
        return cfg.installDir;
    }

    // 3. Fallback to default
    return getDefaultInstallDir();
}

bool LauncherCore::saveInstallDir(const std::string& dir) {
    ConfigData cfg = loadConfig();
    cfg.installDir = dir;
    return saveConfig(cfg);
}

std::string LauncherCore::pickFolderDialog(void* nativeWindowHandle) {
#ifdef _WIN32
    HWND owner = static_cast<HWND>(nativeWindowHandle);
    std::string result = "";
    IFileOpenDialog* pFileOpen = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_ALL, IID_IFileOpenDialog, reinterpret_cast<void**>(&pFileOpen));
    if (SUCCEEDED(hr)) {
        DWORD dwOptions;
        if (SUCCEEDED(pFileOpen->GetOptions(&dwOptions))) {
            pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
        }
        pFileOpen->SetTitle(L"Seleccionar carpeta de instalacion para Nebula");
        hr = pFileOpen->Show(owner);
        if (SUCCEEDED(hr)) {
            IShellItem* pItem = nullptr;
            hr = pFileOpen->GetResult(&pItem);
            if (SUCCEEDED(hr)) {
                PWSTR pszFilePath = nullptr;
                hr = pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszFilePath);
                if (SUCCEEDED(hr) && pszFilePath) {
                    result = toUtf8(pszFilePath);
                    CoTaskMemFree(pszFilePath);
                }
                pItem->Release();
            }
        }
        pFileOpen->Release();
    }
    return result;
#else
    std::string result = "";
    FILE* fp = popen("zenity --file-selection --directory --title=\"Seleccionar carpeta de instalacion\" 2>/dev/null "
                     "|| kdialog --getexistingdirectory \"$HOME\" --title \"Seleccionar carpeta de instalacion\" 2>/dev/null", "r");
    if (fp) {
        char buf[1024];
        if (fgets(buf, sizeof(buf), fp)) {
            result = buf;
            result.erase(result.find_last_not_of(" \t\r\n") + 1);
        }
        pclose(fp);
    }
    return result;
#endif
}

bool LauncherCore::validateAndNormalizePath(
    const std::string& inputPath,
    std::string& outNormalizedPath,
    std::string& outError
) {
    if (inputPath.empty()) {
        outError = "La ruta no puede estar vacia.";
        return false;
    }

    try {
        fs::path p = fs::path(inputPath).lexically_normal();

        // Check if path is only a drive or filesystem root
        if (p.has_root_path() && p.root_path() == p) {
            p /= "Nebula";
        } else {
            // Check leaf name: if not ending with nebula/Nebula, append Nebula
            std::string leaf = p.filename().string();
            std::string leafLower = leaf;
            std::transform(leafLower.begin(), leafLower.end(), leafLower.begin(), ::tolower);
            if (leafLower != "nebula") {
                p /= "Nebula";
            }
        }

        std::string finalPath = p.string();

#ifdef _WIN32
        std::string lowerPath = finalPath;
        std::transform(lowerPath.begin(), lowerPath.end(), lowerPath.begin(), ::tolower);
        if (lowerPath.find(":\\windows") != std::string::npos ||
            lowerPath.find("system32") != std::string::npos) {
            outError = "No se permite instalar directamente en una carpeta del sistema de Windows.";
            return false;
        }
#else
        if (finalPath.rfind("/bin", 0) == 0 ||
            finalPath.rfind("/usr/bin", 0) == 0 ||
            finalPath.rfind("/etc", 0) == 0 ||
            finalPath.rfind("/sbin", 0) == 0) {
            outError = "No se permite instalar en directorios criticos del sistema.";
            return false;
        }
#endif

        // Test if directory can be created and is writable
        std::error_code ec;
        fs::create_directories(p, ec);
        if (ec) {
            outError = "No se tienen permisos para crear la carpeta: " + ec.message();
            return false;
        }

        // Test write probe
        fs::path testFile = p / ".write_probe.tmp";
        {
            std::ofstream testStream(testFile.string());
            if (!testStream.is_open()) {
                outError = "No hay permisos de escritura en la carpeta seleccionada.";
                return false;
            }
            testStream << "ok" << std::endl;
        }
        fs::remove(testFile, ec);

        outNormalizedPath = finalPath;
        return true;
    } catch (const std::exception& e) {
        outError = std::string("Ruta invalida: ") + e.what();
        return false;
    }
}

bool LauncherCore::extractReleaseZipSafe(
    const std::string& zipPath,
    const std::string& targetInstallDir,
    std::string& outError
) {
    try {
        fs::path installPath(targetInstallDir);
        fs::path appDir = installPath / "app";
        fs::path tempAppDir = installPath / "app_temp_unpack";
        fs::path backupAppDir = installPath / "app_old_backup";

        // Clean any leftover temp folders from previous runs
        std::error_code ec;
        if (fs::exists(tempAppDir)) {
            fs::remove_all(tempAppDir, ec);
        }
        if (fs::exists(backupAppDir)) {
            fs::remove_all(backupAppDir, ec);
        }

        fs::create_directories(tempAppDir, ec);

        // Terminate any running nebula app before extraction
        terminateRunningApp(targetInstallDir);

        // 1. Extract zip into tempAppDir
        if (!extractReleaseZip(zipPath, tempAppDir.string(), outError)) {
            fs::remove_all(tempAppDir, ec);
            return false;
        }

        // 2. Validate that executable was created
        std::string expectedExe = 
#ifdef _WIN32
            (tempAppDir / "nebula.exe").string();
#else
            (tempAppDir / "nebula").string();
#endif
        if (!fs::exists(expectedExe)) {
            outError = "El paquete descargado no contiene un ejecutable valido de Nebula.";
            fs::remove_all(tempAppDir, ec);
            return false;
        }

        // 3. Atomic swap: backup existing app if present, then move tempAppDir to app
        bool hadOldApp = false;
        if (fs::exists(appDir)) {
            hadOldApp = true;
            fs::rename(appDir, backupAppDir, ec);
            if (ec) {
                outError = "No se pudo preparar la actualizacion (archivos en uso): " + ec.message();
                fs::remove_all(tempAppDir, ec);
                return false;
            }
        }

        fs::rename(tempAppDir, appDir, ec);
        if (ec) {
            // Swap failed! Restore old app
            if (hadOldApp && fs::exists(backupAppDir)) {
                fs::rename(backupAppDir, appDir, ec);
            }
            outError = "Fallo al aplicar la nueva version: " + ec.message();
            return false;
        }

        // 4. Cleanup old backup safely
        if (fs::exists(backupAppDir)) {
            fs::remove_all(backupAppDir, ec);
        }

#ifndef _WIN32
        fs::path finalExe = appDir / "nebula";
        if (fs::exists(finalExe)) {
            chmod(finalExe.c_str(), 0755);
        }
#endif

        // 5. Self-update: check if the release package includes an updated launcher binary
        std::string launcherName = 
#ifdef _WIN32
            "NebulaLauncher.exe";
#else
            "NebulaLauncher";
#endif
        fs::path bundledLauncher = appDir / launcherName;
        if (fs::exists(bundledLauncher)) {
            fs::path installedLauncher = installPath / launcherName;
#ifdef _WIN32
            fs::path oldLauncher = installPath / (launcherName + ".old");
            if (fs::exists(oldLauncher)) {
                fs::remove(oldLauncher, ec);
            }
            if (fs::exists(installedLauncher)) {
                fs::rename(installedLauncher, oldLauncher, ec);
            }
            fs::copy_file(bundledLauncher, installedLauncher, fs::copy_options::overwrite_existing, ec);
            fs::remove(bundledLauncher, ec);
#else
            fs::rename(bundledLauncher, installedLauncher, ec);
            chmod(installedLauncher.c_str(), 0755);
#endif
        }

        return true;
    } catch (const std::exception& e) {
        outError = std::string("Error critico en la extraccion: ") + e.what();
        return false;
    }
}

bool LauncherCore::migrateInstallation(
    const std::string& sourceInstallDir,
    const std::string& destInstallDir,
    std::string& outError
) {
    if (sourceInstallDir == destInstallDir) return true;

    try {
        fs::path srcApp = fs::path(sourceInstallDir) / "app";
        fs::path destApp = fs::path(destInstallDir) / "app";

        if (!fs::exists(srcApp)) {
            outError = "No se encontro una instalacion previa para mover en: " + sourceInstallDir;
            return false;
        }

        terminateRunningApp(sourceInstallDir);

        std::error_code ec;
        fs::create_directories(destInstallDir, ec);

        // Safely copy app to new location
        fs::copy(srcApp, destApp, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
        if (ec) {
            outError = "Error al copiar los archivos a la nueva ubicacion: " + ec.message();
            return false;
        }

#ifndef _WIN32
        fs::path destExe = destApp / "nebula";
        if (fs::exists(destExe)) {
            chmod(destExe.c_str(), 0755);
        }
#endif

        // Copy version file if present
        std::string ver = getInstalledVersion(sourceInstallDir);
        if (!ver.empty()) {
            setInstalledVersion(destInstallDir, ver);
        }

        // Update shortcuts for the new destination
        installShortcuts(destInstallDir, outError);

        // Save new install directory in configuration
        saveInstallDir(destInstallDir);

        // Verify that destination executable exists before removing source
        if (isAppInstalled(destInstallDir)) {
            fs::remove_all(srcApp, ec);
            fs::remove(getVersionFilePath(sourceInstallDir), ec);
        }

        return true;
    } catch (const std::exception& e) {
        outError = std::string("Error durante la migracion: ") + e.what();
        return false;
    }
}

bool LauncherCore::registerUninstallEntry(
    const std::string& installDir,
    const std::string& version,
    std::string& outError
) {
#ifdef _WIN32
    HKEY hKey = NULL;
    const wchar_t* subKey = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Nebula";
    LONG res = RegCreateKeyExW(HKEY_CURRENT_USER, subKey, 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL);
    if (res != ERROR_SUCCESS) {
        outError = "No se pudo registrar en Windows (codigo " + std::to_string(res) + ")";
        return false;
    }

    std::wstring wDisplayName = L"Nebula";
    std::wstring wDisplayVersion = toWide(version);
    std::wstring wPublisher = L"TG12r";
    std::wstring wInstallLocation = toWide(installDir);
    std::string launcherExe = getLauncherExecutablePath(installDir);
    std::wstring wDisplayIcon = toWide(launcherExe);
    std::wstring wUninstallString = L"\"" + toWide(launcherExe) + L"\" --uninstall";
    std::wstring wQuietUninstall = L"\"" + toWide(launcherExe) + L"\" --uninstall --silent";
    DWORD dwordOne = 1;
    DWORD dwordZero = 0;
    DWORD estimatedSizeKB = 55000;

    RegSetValueExW(hKey, L"DisplayName", 0, REG_SZ, (const BYTE*)wDisplayName.c_str(), (DWORD)((wDisplayName.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"DisplayVersion", 0, REG_SZ, (const BYTE*)wDisplayVersion.c_str(), (DWORD)((wDisplayVersion.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"Publisher", 0, REG_SZ, (const BYTE*)wPublisher.c_str(), (DWORD)((wPublisher.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"InstallLocation", 0, REG_SZ, (const BYTE*)wInstallLocation.c_str(), (DWORD)((wInstallLocation.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"DisplayIcon", 0, REG_SZ, (const BYTE*)wDisplayIcon.c_str(), (DWORD)((wDisplayIcon.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"UninstallString", 0, REG_SZ, (const BYTE*)wUninstallString.c_str(), (DWORD)((wUninstallString.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"QuietUninstallString", 0, REG_SZ, (const BYTE*)wQuietUninstall.c_str(), (DWORD)((wQuietUninstall.length() + 1) * sizeof(wchar_t)));
    RegSetValueExW(hKey, L"NoModify", 0, REG_DWORD, (const BYTE*)&dwordOne, sizeof(DWORD));
    RegSetValueExW(hKey, L"NoRepair", 0, REG_DWORD, (const BYTE*)&dwordZero, sizeof(DWORD));
    RegSetValueExW(hKey, L"EstimatedSize", 0, REG_DWORD, (const BYTE*)&estimatedSizeKB, sizeof(DWORD));

    RegCloseKey(hKey);
    return true;
#else
    (void)installDir;
    (void)version;
    (void)outError;
    return true;
#endif
}

bool LauncherCore::unregisterUninstallEntry(std::string& outError) {
#ifdef _WIN32
    LONG res = RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Nebula");
    if (res != ERROR_SUCCESS && res != ERROR_FILE_NOT_FOUND) {
        outError = "Fallo al remover clave de desinstalacion en el registro.";
        return false;
    }
    return true;
#else
    (void)outError;
    return true;
#endif
}

bool LauncherCore::uninstallApp(const std::string& installDir, std::string& outError) {
    try {
        // 1. Terminar procesos activos de Nebula en la carpeta de instalacion
        terminateRunningApp(installDir);

        // 2. Eliminar accesos directos
#ifdef _WIN32
        wchar_t desktopPath[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_DESKTOPDIRECTORY, NULL, 0, desktopPath))) {
            fs::path dPath(desktopPath);
            dPath /= "Nebula.lnk";
            std::error_code ec;
            fs::remove(dPath, ec);
        }
        wchar_t programsPath[MAX_PATH];
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PROGRAMS, NULL, 0, programsPath))) {
            fs::path pPath(programsPath);
            pPath /= "Nebula.lnk";
            std::error_code ec;
            fs::remove(pPath, ec);
        }
#else
        const char* home = std::getenv("HOME");
        if (home) {
            fs::path desktopFile = fs::path(home) / ".local" / "share" / "applications" / "nebula.desktop";
            std::error_code ec;
            fs::remove(desktopFile, ec);
        }
#endif

        // 3. Remover clave del registro
        unregisterUninstallEntry(outError);

        // 4. Remover carpeta app y version
        std::error_code ec;
        fs::path appDir = fs::path(installDir) / "app";
        if (fs::exists(appDir)) {
            fs::remove_all(appDir, ec);
        }
        fs::path vFile = getVersionFilePath(installDir);
        fs::remove(vFile, ec);
        fs::path cfgFile = getConfigFilePath();
        fs::remove(cfgFile, ec);

        // 5. En Windows, si el ejecutable actual esta en installDir, lanzar eliminacion diferida del directorio
#ifdef _WIN32
        std::string currentExe = getCurrentExecutablePath();
        if (!currentExe.empty() && fs::exists(currentExe)) {
            std::wstring cmd = L"cmd.exe /c timeout /t 2 /nobreak > NUL & rmdir /s /q \"" + toWide(installDir) + L"\"";
            STARTUPINFOW si = { sizeof(si) };
            si.dwFlags = STARTF_USESHOWWINDOW;
            si.wShowWindow = SW_HIDE;
            PROCESS_INFORMATION pi = { 0 };
            if (CreateProcessW(NULL, &cmd[0], NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
                CloseHandle(pi.hProcess);
                CloseHandle(pi.hThread);
            }
        }
#endif
        return true;
    } catch (const std::exception& e) {
        outError = e.what();
        return false;
    }
}

} // namespace NebulaLauncher
