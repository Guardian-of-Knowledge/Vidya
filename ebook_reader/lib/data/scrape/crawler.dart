// lib/data/scrape/crawler.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../core/logger.dart';
import 'html_extractor.dart';

class WebBookDraft {
  final String title;
  final List<WebChapter> chapters;
  WebBookDraft({required this.title, required this.chapters});
}

class CrawlProgress {
  final int fetched;
  final Uri? current;
  final String status;
  const CrawlProgress({required this.fetched, this.current, this.status = ''});
}

typedef ProgressCb = void Function(CrawlProgress p);

class Crawler {
  final Duration requestTimeout;
  final Duration politenessDelay;
  final Map<String, String> headers;

  /// If set on web, requests are routed to `http://host:port?url=<encoded>`.
  final String? proxyBase;

  Crawler({
    this.requestTimeout = const Duration(seconds: 15),
    this.politenessDelay = const Duration(milliseconds: 800),
    this.proxyBase,
    Map<String, String>? headers,
  }) : headers = {
          'User-Agent': 'VidyaCrawler/1.0 (+https://example.invalid)',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          ...?headers,
        };

  Future<WebBookDraft> crawl({
    required Uri start,
    String? forcedTitle,
    required SiteConfig config,
    required int maxChapters,
    ProgressCb? onProgress,
    bool stopOnDuplicate = false, // NOTE: now false by default
  }) async {
    final seenUrls = <Uri>{};
    final chapters = <WebChapter>[];
    Uri? url = start;
    int guard = 0;

    LogStore.log('crawl: start=$start, max=$maxChapters, proxyBase=$proxyBase');

    while (url != null && chapters.length < maxChapters && guard < maxChapters * 4) {
      guard++;
      if (seenUrls.contains(url)) {
        onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'Loop detected, stopping.'));
        LogStore.log('Loop detected for $url, stopping.');
        break;
      }
      seenUrls.add(url);

      onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'GET'));
      final html = await _fetch(url);
      if (html == null || html.trim().isEmpty) {
        onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'Empty/failed response'));
        LogStore.log('HTTP empty/failed for $url');
        break;
      }
      LogStore.log('GET $url -> ok (${html.length} bytes)');

      final ch = extractChapter(html, url, config: config);
      if (ch == null || ch.contentHtml.trim().isEmpty) {
        onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'No content; trying next'));
        LogStore.log('No content extracted at $url');
        url = ch?.nextUrl;
        await Future.delayed(politenessDelay);
        continue;
      }

      // *** FIX: do NOT stop just because titles repeat (NovelBin repeats book title) ***
      // Keep only a very light duplicate guard on exact same URL/content prefix.
      final prefixLen = ch.contentHtml.length < 180 ? ch.contentHtml.length : 180;
      final head = ch.contentHtml.substring(0, prefixLen);
      final isDup = chapters.any((x) => x.contentHtml.startsWith(head));
      if (stopOnDuplicate && isDup) {
        onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'Duplicate content; stop'));
        LogStore.log('Duplicate content detected, stopping at $url');
        break;
      }

      chapters.add(ch);
      onProgress?.call(CrawlProgress(fetched: chapters.length, current: url, status: 'OK'));
      LogStore.log('Added chapter "${ch.title}" (${ch.contentHtml.length} chars)');

      url = ch.nextUrl;
      if (url == null) LogStore.log('No next URL from this page.');
      await Future.delayed(politenessDelay);
    }

    final title = (forcedTitle ?? (chapters.isNotEmpty ? chapters.first.title : 'Imported Book')).trim();
    final finalTitle = title.isEmpty ? 'Imported Book' : title;

    LogStore.log('crawl: done. chapters=${chapters.length}, title="$finalTitle"');
    return WebBookDraft(title: finalTitle, chapters: chapters);
  }

  Future<String?> _fetch(Uri url) async {
    try {
      if (proxyBase != null && proxyBase!.isNotEmpty) {
        final proxied = Uri.parse(proxyBase!).replace(queryParameters: {'url': url.toString()});
        LogStore.log('Proxy GET $proxied');
        final res = await http.get(proxied, headers: headers).timeout(requestTimeout);
        if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
        LogStore.log('Proxy HTTP ${res.statusCode} for $url');
        return null;
      } else {
        final res = await http.get(url, headers: headers).timeout(requestTimeout);
        if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
        LogStore.log('HTTP ${res.statusCode} for $url');
        return null;
      }
    } catch (e) {
      LogStore.log('ClientException: $e for $url');
      return null;
    }
  }
}
