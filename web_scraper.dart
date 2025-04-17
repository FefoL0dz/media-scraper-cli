import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'url_list_holder.dart';

Future<void> main() async {
  DateTime begin = DateTime.now();
  // for (final url in UrlListHolder.urls) {
  //   await downloadMediaFiles(url);
  // }
  await downloadMediaFiles('https://www.example.com/path');
  print('Script finished! in ${DateTime.now().difference(begin).inMinutes}');
  exit(0);
}

Future<void> downloadMediaFiles(String url) async {
  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      String body = response.body;

      final mediaPattern = RegExp(r'(https?:\/\/[^\s\"<>]+?\.(png|jpe?g|gif|mp4))', caseSensitive: false);

      Iterable<RegExpMatch> matches = mediaPattern.allMatches(body);
      List<String> mediaUrls = matches.map((m) => m.group(0)!).toList();

      if (mediaUrls.isEmpty) {
        print('No media files found. \nSource: $url');
        return;
      }

      var folderName = url.replaceAll(RegExp(r'https?://'), '').replaceAll(RegExp(r'[^\w\d]'), '_').toUpperCase();
      var dir = Directory(folderName);
      if (!dir.existsSync()) {
        dir.createSync();
      }

      int totalItems = mediaUrls.length;
      int completedItems = 0;

      for (var mediaUrl in mediaUrls) {
        stdout.write("\n");
        await downloadFile(mediaUrl, dir.path, url, totalItems, completedItems);
        completedItems++;
        updateProgressBar('Overall Progress', completedItems, totalItems, clearTerminal: true);
      }
      print('\nAll downloads complete.');
    } else {
      print('Failed to load the page. Status code: ${response.statusCode} \nSource: $url');
    }
  } catch (e) {
    print('Error: $e');
  }
}

Future<void> downloadFile(String mediaUrl, String directory, String originalUrl, int totalItems, int completedItems, {int maxRetries = 3}) async {
  int attempt = 0;
  bool success = false;

  var fileName = path.basename(mediaUrl);
  var filePath = path.join(directory, fileName);
  File file = File(filePath);

  while (attempt < maxRetries && !success) {
    attempt++;
    try {
      int downloadedBytes = 0;

      if (file.existsSync()) {
        downloadedBytes = file.lengthSync();
      }

      final request = http.Request('GET', Uri.parse(mediaUrl));
      request.headers.addAll({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36',
        'Referer': originalUrl,
        if (downloadedBytes > 0) 'Range': 'bytes=$downloadedBytes-',
      });

      final response = await request.send();

      if (response.statusCode == 206 || response.statusCode == 200) {
        final totalBytes = response.contentLength != null ? response.contentLength! + downloadedBytes : null;
        final List<int> bytes = [];
        int receivedBytes = downloadedBytes;

        IOSink sink = file.openWrite(mode: FileMode.append);

        await response.stream.listen((List<int> newBytes) {
          bytes.addAll(newBytes);
          sink.add(newBytes);

          receivedBytes += newBytes.length;
          if (totalBytes != null) {
            updateProgressBar('Downloading $fileName', receivedBytes, totalBytes, clearTerminal: true);
          }
        }).asFuture<void>();

        await sink.flush();
        await sink.close();

        print('Downloaded: $filePath');
        success = true;
      } else {
        print('Failed to download $mediaUrl. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading $mediaUrl: $e');
      if (attempt < maxRetries) {
        print('Retrying ($attempt/$maxRetries)...');
      } else {
        print('Failed after $maxRetries attempts.');
      }
    }
  }
}

void updateProgressBar(String label, int current, int total, {int barLength = 40, bool clearTerminal = false}) {
  if (clearTerminal) {
    clearScreen();
  }

  final double progress = current / total;
  final int filledLength = (barLength * progress).round();
  final String bar = '=' * filledLength + '-' * (barLength - filledLength);
  final percent = (progress * 100).toStringAsFixed(1);

  stdout.write('\r$label: $percent% |$bar|');
}

void clearScreen() {
  if (Platform.isWindows) {
    Process.runSync("cls", [], runInShell: true);
  } else {
    stdout.write('\x1B[2J\x1B[0;0H');
  }
}
