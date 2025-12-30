import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:version/version.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  static UpdateService get instance => _instance;

  UpdateService._internal();

  final String _repoOwner = 'TG12r';
  final String _repoName = 'nebula';

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = Version.parse(packageInfo.version);

      final url = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final releaseData = jsonDecode(response.body);
        final String tagName = releaseData['tag_name'];
        final cleanTag = tagName.startsWith('v')
            ? tagName.substring(1)
            : tagName;
        final latestVersion = Version.parse(cleanTag);

        if (latestVersion > currentVersion) {
          if (context.mounted) {
            _showUpdateDialog(
              context,
              tagName,
              releaseData['html_url'],
              releaseData['assets'],
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking for updates: $e");
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    String version,
    String releaseUrl,
    List<dynamic> assets,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
          side: const BorderSide(color: Colors.white, width: 1),
        ),
        title: const Text(
          "UPDATE AVAILABLE",
          style: TextStyle(color: Colors.white, fontFamily: 'Courier'),
        ),
        content: Text(
          "New version $version is available.\ncurrent version is older.",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("IGNORE", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _launchUpdate(context, releaseUrl, assets);
            },
            child: const Text(
              "UPDATE NOW",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUpdate(
    BuildContext context,
    String releaseUrl,
    List<dynamic> assets,
  ) async {
    if (Platform.isAndroid) {
      String? apkUrl;
      for (var asset in assets) {
        if (asset['name'].toString().endsWith('.apk')) {
          apkUrl = asset['browser_download_url'];
          break;
        }
      }

      if (apkUrl != null) {
        await _downloadAndInstallApk(context, apkUrl);
      } else {
        _launchUrl(releaseUrl);
      }
    } else {
      _launchUrl(releaseUrl);
    }
  }

  Future<void> _downloadAndInstallApk(BuildContext context, String url) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _DownloadProgressDialog(),
      );

      final dir = await getTemporaryDirectory();
      final filePath = "${dir.path}/update.apk";
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      await Dio().download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _downloadProgressNotifier.value = received / total;
          }
        },
      );

      if (context.mounted) {
        Navigator.pop(context);
      }

      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        debugPrint("Install failed: ${result.message}");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Install error: ${result.message}")),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
      }
      debugPrint("Download error: $e");
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      debugPrint("Error launching URL: $e");
    }
  }
}

final ValueNotifier<double> _downloadProgressNotifier = ValueNotifier(0.0);

class _DownloadProgressDialog extends StatelessWidget {
  const _DownloadProgressDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Colors.white),
      ),
      title: const Text(
        "DOWNLOADING...",
        style: TextStyle(color: Colors.white, fontFamily: 'Courier'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _downloadProgressNotifier,
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white10,
                color: Colors.white,
              );
            },
          ),
          const SizedBox(height: 10),
          const Text("Please wait...", style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
