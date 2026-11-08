#pragma once

#include <string>
#include <filesystem>
#include <vector>

namespace NebulaLauncher {

class LauncherCore {
public:
    static std::string getDefaultInstallDir();
    static std::string getAppDir(const std::string& installDir);
    static std::string getAppExecutablePath(const std::string& installDir);
    static std::string getLauncherExecutablePath(const std::string& installDir);
    static std::string getVersionFilePath(const std::string& installDir);

    static bool isAppInstalled(const std::string& installDir);
    static std::string getInstalledVersion(const std::string& installDir);
    static bool setInstalledVersion(const std::string& installDir, const std::string& version);

    // Configuration file & cache
    struct ConfigData {
        std::string installDir;
        int64_t lastCheckTimestamp = 0;
        std::string lastReleaseTag;
        std::string lastReleaseVersion;
        std::string lastAssetName;
        std::string lastDownloadUrl;
        size_t lastAssetSize = 0;
    };

    static std::string getConfigFilePath();
    static ConfigData loadConfig();
    static bool saveConfig(const ConfigData& cfg);
    static std::string getSavedInstallDir();
    static bool saveInstallDir(const std::string& dir);

    // Native OS folder picker dialog
    static std::string pickFolderDialog(void* nativeWindowHandle);

    // Path validation and safety
    static bool validateAndNormalizePath(
        const std::string& inputPath,
        std::string& outNormalizedPath,
        std::string& outError
    );

    // Atomic / Safe release extraction
    static bool extractReleaseZipSafe(
        const std::string& zipPath,
        const std::string& targetInstallDir,
        std::string& outError
    );

    // Migrate existing installation to new folder safely
    static bool migrateInstallation(
        const std::string& sourceInstallDir,
        const std::string& destInstallDir,
        std::string& outError
    );

    // Unpacks release zip into appDir and normalizes folder layout
    static bool extractReleaseZip(
        const std::string& zipPath,
        const std::string& targetAppDir,
        std::string& outError
    );

    // Installs desktop & start menu shortcuts and copies launcher binary
    static bool installShortcuts(
        const std::string& installDir,
        std::string& outError
    );

    // Windows Registry Uninstall registration (HKCU)
    static bool registerUninstallEntry(
        const std::string& installDir,
        const std::string& version,
        std::string& outError
    );
    static bool unregisterUninstallEntry(std::string& outError);
    static bool uninstallApp(
        const std::string& installDir,
        std::string& outError
    );

    // Launches the installed Nebula app
    static bool launchApp(
        const std::string& installDir,
        std::string& outError
    );

    // Process checks
    static bool isAppRunning(const std::string& installDir = "");
    static bool terminateRunningApp(const std::string& installDir = "");

    // Get path to current running launcher exe
    static std::string getCurrentExecutablePath();
};

#ifdef _WIN32
std::wstring toWide(const std::string& str);
std::string toUtf8(const std::wstring& wstr);
#endif

} // namespace NebulaLauncher
