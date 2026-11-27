import 'dart:convert';

/// 업데이트 안내 카드의 한 장.
class ReleaseNotePage {
  const ReleaseNotePage({required this.title, this.body = '', this.image, this.icon});

  final String title;
  final String body;

  /// 앱에 든 그림(`asset/...`) 또는 `https://` 주소. 없으면 [icon]을 보여준다.
  final String? image;

  /// 아이콘 이름 (카드 위젯의 목록에 있는 것)
  final String? icon;
}

/// 한 버전의 안내. 앱에 든 `asset/release_notes.json`과
/// Remote Config `release_note`가 같은 형식을 쓴다.
class ReleaseNote {
  const ReleaseNote({required this.version, required this.pages});

  /// 장이 많으면 끝까지 보지 않으므로 3장까지만 쓴다.
  static const int maxPages = 3;

  final String version;
  final List<ReleaseNotePage> pages;

  /// 형식이 틀리면 null. 제목 없는 장은 버리고 [maxPages]장까지만 담는다.
  static ReleaseNote? tryParse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;

    final version = json['version'];
    final pages = json['pages'];
    if (version is! String || version.trim().isEmpty || pages is! List) return null;

    return ReleaseNote(
      version: version.trim(),
      pages: pages.whereType<Map<String, dynamic>>().map(_page).nonNulls.take(maxPages).toList(),
    );
  }

  static ReleaseNotePage? _page(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      return value is String ? value.trim() : '';
    }

    final title = text('title');
    if (title.isEmpty) return null;

    final image = text('image');
    final icon = text('icon');
    return ReleaseNotePage(
      title: title,
      body: text('body'),
      image: image.startsWith('asset/') || image.startsWith('https://') ? image : null,
      icon: icon.isEmpty ? null : icon,
    );
  }
}
