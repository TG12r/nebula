#pragma once

#include <string>
#include <functional>
#include <atomic>
#include <vector>

namespace NebulaLauncher {

struct ReleaseInfo {
    std::string tag;
    std::string version;       // e.g. "1.2.0"
    std::string assetName;     // e.g. "nebula.v1.2.0.windows.zip"
    std::string downloadUrl;   // direct browser_download_url
    size_t assetSize = 0;
    std::string htmlUrl;
    std::string releaseBody;
};

class Downloader {
public:
    // Simple HTTP GET returning body as string
    static bool httpGet(
        const std::string& url,
        std::string& outResponse,
        std::string& outError
    );

    // Download a file with progress callback (downloadedBytes, totalBytes)
    static bool downloadFile(
        const std::string& url,
        const std::string& destFilePath,
        std::function<void(size_t downloaded, size_t total)> progressCallback,
        std::atomic<bool>& cancelFlag,
        std::string& outError
    );

    // Fetch latest release from GitHub (TG12r/nebula)
    static bool fetchLatestRelease(
        ReleaseInfo& outRelease,
        std::string& outError
    );

    // Compare two semantic versions (e.g. "1.2.1" > "1.2.0")
    static bool isNewerVersion(const std::string& remoteVer, const std::string& localVer);
};

} // namespace NebulaLauncher
