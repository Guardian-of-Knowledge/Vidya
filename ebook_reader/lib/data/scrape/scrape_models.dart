// lib/data/scrape/scrape_models.dart
import 'package:meta/meta.dart';

@immutable
class SiteConfig {
  final String titleSelector;     // CSS selector for chapter/page title
  final String contentSelector;   // CSS selector for the main chapter content
  final String nextLinkSelector;  // CSS selector for the "next chapter" link <a>

  // Optional: clean-up selectors to remove ads/footers within content
  final List<String> removeSelectors;

  const SiteConfig({
    required this.titleSelector,
    required this.contentSelector,
    required this.nextLinkSelector,
    this.removeSelectors = const [],
  });

  SiteConfig copyWith({
    String? titleSelector,
    String? contentSelector,
    String? nextLinkSelector,
    List<String>? removeSelectors,
  }) {
    return SiteConfig(
      titleSelector: titleSelector ?? this.titleSelector,
      contentSelector: contentSelector ?? this.contentSelector,
      nextLinkSelector: nextLinkSelector ?? this.nextLinkSelector,
      removeSelectors: removeSelectors ?? this.removeSelectors,
    );
  }
}

@immutable
class WebChapter {
  final String url;
  final String title;
  final String plainText; // already cleaned of HTML tags
  final int index;

  const WebChapter({
    required this.url,
    required this.title,
    required this.plainText,
    required this.index,
  });
}

@immutable
class WebBookDraft {
  final String startUrl;
  final String bookTitle; // inferred or provided by user
  final List<WebChapter> chapters;

  const WebBookDraft({
    required this.startUrl,
    required this.bookTitle,
    required this.chapters,
  });

  WebBookDraft copyWith({
    String? startUrl,
    String? bookTitle,
    List<WebChapter>? chapters,
  }) {
    return WebBookDraft(
      startUrl: startUrl ?? this.startUrl,
      bookTitle: bookTitle ?? this.bookTitle,
      chapters: chapters ?? this.chapters,
    );
  }
}
