#include <downloader.hpp>
#include <nlohmann/json.hpp>

#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#else
#include <curl/curl.h>
#endif

namespace NebulaLauncher {

static std::string trimVersion(const std::string& v) {
    std::string s = v;
    if (!s.empty() && (s[0] == 'v' || s[0] == 'V')) {
        s = s.substr(1);
    }
    return s;
}

static std::vector<int> parseSemver(const std::string& v) {
    std::string clean = trimVersion(v);
    std::vector<int> parts;
    std::stringstream ss(clean);
    std::string item;
    while (std::getline(ss, item, '.')) {
        try {
            parts.push_back(std::stoi(item));
        } catch (...) {
            parts.push_back(0);
        }
    }
    while (parts.size() < 3) {
        parts.push_back(0);
    }
    return parts;
}

bool Downloader::isNewerVersion(const std::string& remoteVer, const std::string& localVer) {
    if (localVer.empty()) return true;
    std::vector<int> r = parseSemver(remoteVer);
    std::vector<int> l = parseSemver(localVer);
    for (size_t i = 0; i < std::max(r.size(), l.size()); ++i) {
        int rVal = (i < r.size()) ? r[i] : 0;
        int lVal = (i < l.size()) ? l[i] : 0;
        if (rVal > lVal) return true;
        if (rVal < lVal) return false;
    }
    return false;
}

#ifdef _WIN32

static std::wstring toWideString(const std::string& str) {
    if (str.empty()) return L"";
    int count = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.length(), NULL, 0);
    std::wstring wstr(count, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.length(), &wstr[0], count);
    return wstr;
}

static std::string toUtf8String(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int count = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(), NULL, 0, NULL, NULL);
    std::string str(count, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.length(), &str[0], count, NULL, NULL);
    return str;
}

bool Downloader::httpGet(const std::string& url, std::string& outResponse, std::string& outError) {
    std::wstring wUrl = toWideString(url);

    URL_COMPONENTSW urlComp = {0};
    urlComp.dwStructSize = sizeof(urlComp);
    urlComp.dwHostNameLength = (DWORD)-1;
    urlComp.dwUrlPathLength = (DWORD)-1;
    urlComp.dwExtraInfoLength = (DWORD)-1;

    if (!WinHttpCrackUrl(wUrl.c_str(), (DWORD)wUrl.length(), 0, &urlComp)) {
        outError = "URL invalida: " + url;
        return false;
    }

    std::wstring host(urlComp.lpszHostName, urlComp.dwHostNameLength);
    std::wstring path(urlComp.lpszUrlPath, urlComp.dwUrlPathLength + urlComp.dwExtraInfoLength);
    INTERNET_PORT port = urlComp.nPort;
    bool isHttps = (urlComp.nScheme == INTERNET_SCHEME_HTTPS);

    HINTERNET hSession = WinHttpOpen(
        L"NebulaLauncher/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if (!hSession) {
        outError = "Fallo al inicializar WinHttp";
        return false;
    }

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), port, 0);
    if (!hConnect) {
        WinHttpCloseHandle(hSession);
        outError = "Fallo al conectar con el servidor: " + toUtf8String(host);
        return false;
    }

    HINTERNET hRequest = WinHttpOpenRequest(
        hConnect,
        L"GET",
        path.c_str(),
        NULL,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        isHttps ? WINHTTP_FLAG_SECURE : 0
    );
    if (!hRequest) {
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        outError = "Fallo al crear solicitud HTTP";
        return false;
    }

    DWORD redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_REDIRECT_POLICY, &redirectPolicy, sizeof(redirectPolicy));

    // GitHub API requires a User-Agent header
    std::wstring headers = L"User-Agent: NebulaLauncher/1.0\r\nAccept: application/vnd.github.v3+json\r\n";

    BOOL bResults = WinHttpSendRequest(
        hRequest,
        headers.c_str(),
        (DWORD)headers.length(),
        WINHTTP_NO_REQUEST_DATA,
        0,
        0,
        0
    );

    if (bResults) {
        bResults = WinHttpReceiveResponse(hRequest, NULL);
    }

    if (!bResults) {
        DWORD err = GetLastError();
        outError = "Error en respuesta HTTP: codigo " + std::to_string(err);
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    DWORD statusCode = 0;
    DWORD statusSize = sizeof(statusCode);
    WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);

    if (statusCode != 200) {
        if (statusCode == 403) {
            outError = "Limite de peticiones de GitHub excedido (HTTP 403). Intentalo mas tarde.";
        } else {
            outError = "Servidor respondio con codigo HTTP " + std::to_string(statusCode);
        }
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    std::vector<char> responseBuffer;
    DWORD bytesAvailable = 0;
    while (WinHttpQueryDataAvailable(hRequest, &bytesAvailable) && bytesAvailable > 0) {
        std::vector<char> temp(bytesAvailable);
        DWORD bytesRead = 0;
        if (WinHttpReadData(hRequest, temp.data(), bytesAvailable, &bytesRead) && bytesRead > 0) {
            responseBuffer.insert(responseBuffer.end(), temp.begin(), temp.begin() + bytesRead);
        } else {
            break;
        }
    }

    outResponse.assign(responseBuffer.begin(), responseBuffer.end());

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return true;
}

bool Downloader::downloadFile(
    const std::string& url,
    const std::string& destFilePath,
    std::function<void(size_t downloaded, size_t total)> progressCallback,
    std::atomic<bool>& cancelFlag,
    std::string& outError
) {
    std::wstring wUrl = toWideString(url);

    URL_COMPONENTSW urlComp = {0};
    urlComp.dwStructSize = sizeof(urlComp);
    urlComp.dwHostNameLength = (DWORD)-1;
    urlComp.dwUrlPathLength = (DWORD)-1;
    urlComp.dwExtraInfoLength = (DWORD)-1;

    if (!WinHttpCrackUrl(wUrl.c_str(), (DWORD)wUrl.length(), 0, &urlComp)) {
        outError = "URL de descarga invalida: " + url;
        return false;
    }

    std::wstring host(urlComp.lpszHostName, urlComp.dwHostNameLength);
    std::wstring path(urlComp.lpszUrlPath, urlComp.dwUrlPathLength + urlComp.dwExtraInfoLength);
    INTERNET_PORT port = urlComp.nPort;
    bool isHttps = (urlComp.nScheme == INTERNET_SCHEME_HTTPS);

    HINTERNET hSession = WinHttpOpen(
        L"NebulaLauncher/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if (!hSession) {
        outError = "Fallo al inicializar sesion HTTP";
        return false;
    }

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), port, 0);
    if (!hConnect) {
        WinHttpCloseHandle(hSession);
        outError = "Fallo al conectar con host de descarga";
        return false;
    }

    HINTERNET hRequest = WinHttpOpenRequest(
        hConnect,
        L"GET",
        path.c_str(),
        NULL,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        isHttps ? WINHTTP_FLAG_SECURE : 0
    );
    if (!hRequest) {
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        outError = "Fallo al abrir solicitud de descarga";
        return false;
    }

    DWORD redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_REDIRECT_POLICY, &redirectPolicy, sizeof(redirectPolicy));

    std::wstring headers = L"User-Agent: NebulaLauncher/1.0\r\n";
    BOOL bResults = WinHttpSendRequest(
        hRequest,
        headers.c_str(),
        (DWORD)headers.length(),
        WINHTTP_NO_REQUEST_DATA,
        0,
        0,
        0
    );

    if (bResults) {
        bResults = WinHttpReceiveResponse(hRequest, NULL);
    }

    if (!bResults) {
        outError = "Error al iniciar la descarga desde el servidor";
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    DWORD statusCode = 0;
    DWORD statusSize = sizeof(statusCode);
    WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &statusSize, WINHTTP_NO_HEADER_INDEX);

    if (statusCode != 200) {
        outError = "Descarga rechazada con codigo HTTP " + std::to_string(statusCode);
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    DWORD contentLength = 0;
    DWORD lengthSize = sizeof(contentLength);
    WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &contentLength, &lengthSize, WINHTTP_NO_HEADER_INDEX);

    std::ofstream outFile(destFilePath, std::ios::binary);
    if (!outFile.is_open()) {
        outError = "No se pudo crear archivo destino: " + destFilePath;
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    size_t totalDownloaded = 0;
    std::vector<char> buffer(65536);

    while (!cancelFlag.load()) {
        DWORD bytesAvailable = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &bytesAvailable) || bytesAvailable == 0) {
            break;
        }

        while (bytesAvailable > 0 && !cancelFlag.load()) {
            DWORD toRead = (std::min)((DWORD)buffer.size(), bytesAvailable);
            DWORD bytesRead = 0;
            if (WinHttpReadData(hRequest, buffer.data(), toRead, &bytesRead) && bytesRead > 0) {
                outFile.write(buffer.data(), bytesRead);
                totalDownloaded += bytesRead;
                bytesAvailable -= bytesRead;
                if (progressCallback) {
                    progressCallback(totalDownloaded, (size_t)contentLength);
                }
            } else {
                break;
            }
        }
    }

    outFile.close();
    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);

    if (cancelFlag.load()) {
        std::remove(destFilePath.c_str());
        outError = "Descarga cancelada por el usuario";
        return false;
    }

    return true;
}

#else

// Linux implementation with libcurl
struct CurlStringHelper {
    std::string data;
};

static size_t curlWriteToString(void* contents, size_t size, size_t nmemb, void* userp) {
    size_t totalSize = size * nmemb;
    CurlStringHelper* helper = static_cast<CurlStringHelper*>(userp);
    helper->data.append(static_cast<char*>(contents), totalSize);
    return totalSize;
}

bool Downloader::httpGet(const std::string& url, std::string& outResponse, std::string& outError) {
    CURL* curl = curl_easy_init();
    if (!curl) {
        outError = "No se pudo inicializar cURL";
        return false;
    }

    CurlStringHelper helper;
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "NebulaLauncher/1.0");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curlWriteToString);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &helper);

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        outError = std::string("Error cURL: ") + curl_easy_strerror(res);
        curl_easy_cleanup(curl);
        return false;
    }

    long httpCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
    curl_easy_cleanup(curl);

    if (httpCode != 200) {
        if (httpCode == 403) {
            outError = "Limite de peticiones de GitHub excedido (HTTP 403). Intentalo mas tarde.";
        } else {
            outError = "Servidor respondio con HTTP " + std::to_string(httpCode);
        }
        return false;
    }

    outResponse = helper.data;
    return true;
}

struct CurlFileHelper {
    std::ofstream* stream;
    std::function<void(size_t, size_t)> progress;
    std::atomic<bool>* cancel;
};

static size_t curlWriteToFile(void* contents, size_t size, size_t nmemb, void* userp) {
    CurlFileHelper* helper = static_cast<CurlFileHelper*>(userp);
    if (helper->cancel && helper->cancel->load()) return 0; // abort
    size_t totalSize = size * nmemb;
    helper->stream->write(static_cast<char*>(contents), totalSize);
    return totalSize;
}

static int curlXferInfo(void* clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    CurlFileHelper* helper = static_cast<CurlFileHelper*>(clientp);
    if (helper->cancel && helper->cancel->load()) return 1; // abort
    if (helper->progress && dltotal > 0) {
        helper->progress((size_t)dlnow, (size_t)dltotal);
    }
    return 0;
}

bool Downloader::downloadFile(
    const std::string& url,
    const std::string& destFilePath,
    std::function<void(size_t downloaded, size_t total)> progressCallback,
    std::atomic<bool>& cancelFlag,
    std::string& outError
) {
    CURL* curl = curl_easy_init();
    if (!curl) {
        outError = "No se pudo inicializar cURL";
        return false;
    }

    std::ofstream outFile(destFilePath, std::ios::binary);
    if (!outFile.is_open()) {
        curl_easy_cleanup(curl);
        outError = "No se pudo abrir archivo destino: " + destFilePath;
        return false;
    }

    CurlFileHelper helper;
    helper.stream = &outFile;
    helper.progress = progressCallback;
    helper.cancel = &cancelFlag;

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "NebulaLauncher/1.0");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curlWriteToFile);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &helper);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, curlXferInfo);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &helper);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);

    CURLcode res = curl_easy_perform(curl);
    outFile.close();

    long httpCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
    curl_easy_cleanup(curl);

    if (cancelFlag.load() || res == CURLE_ABORTED_BY_CALLBACK) {
        std::remove(destFilePath.c_str());
        outError = "Descarga cancelada por el usuario";
        return false;
    }

    if (res != CURLE_OK) {
        std::remove(destFilePath.c_str());
        outError = std::string("Error en descarga: ") + curl_easy_strerror(res);
        return false;
    }

    if (httpCode != 200) {
        std::remove(destFilePath.c_str());
        outError = "Servidor respondio con HTTP " + std::to_string(httpCode);
        return false;
    }

    return true;
}

#endif

bool Downloader::fetchLatestRelease(ReleaseInfo& outRelease, std::string& outError) {
    const std::string apiUrl = "https://api.github.com/repos/TG12r/nebula/releases/latest";
    std::string jsonResponse;
    if (!httpGet(apiUrl, jsonResponse, outError)) {
        return false;
    }

    try {
        auto doc = nlohmann::json::parse(jsonResponse);
        if (!doc.contains("tag_name") || !doc.contains("assets")) {
            outError = "Respuesta de GitHub incompleta o formato inesperado";
            return false;
        }

        outRelease.tag = doc["tag_name"].get<std::string>();
        outRelease.version = trimVersion(outRelease.tag);
        outRelease.htmlUrl = doc.value("html_url", "");
        outRelease.releaseBody = doc.value("body", "");

        std::string targetKeyword;
#ifdef _WIN32
        targetKeyword = "windows.zip";
#else
        targetKeyword = "linux.zip";
#endif

        bool assetFound = false;
        for (const auto& asset : doc["assets"]) {
            std::string name = asset.value("name", "");
            std::string lowerName = name;
            std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);

            if (lowerName.find(targetKeyword) != std::string::npos) {
                outRelease.assetName = name;
                outRelease.downloadUrl = asset.value("browser_download_url", "");
                outRelease.assetSize = asset.value("size", (size_t)0);
                assetFound = true;
                break;
            }
        }

        if (!assetFound) {
            outError = "No se encontro paquete portable (" + targetKeyword + ") en la version " + outRelease.tag;
            return false;
        }

        return true;
    } catch (const std::exception& e) {
        outError = std::string("Error al procesar JSON de GitHub: ") + e.what();
        return false;
    }
}

} // namespace NebulaLauncher
