//
//  rss_parser.dart
//
//  Minimal RSS 2.0 and Atom reader. It understands the tags a subscription
//  timeline needs and ignores the rest of the document.
//

class FeedParseException implements Exception {
  const FeedParseException();
}

class ParsedFeed {
  const ParsedFeed({required this.title, required this.entries});

  final String title;
  final List<ParsedFeedEntry> entries;
}

class ParsedFeedEntry {
  const ParsedFeedEntry({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.publishedAt,
    this.link,
  });

  final String id;
  final String title;
  final String excerpt;
  final int publishedAt;
  final String? link;
}

/// Parses an RSS 2.0, RSS 1.0, or Atom document into timeline entries.
///
/// [now] supplies a clock for entries that omit a date, so tests stay stable
/// and document order is preserved (earlier entries sort newer).
ParsedFeed parseRssOrAtom(String source, {DateTime? now}) {
  final document = _XmlDocument.parse(source);
  final root = document.rootElement;
  if (root == null) throw const FeedParseException();
  final feed = _feedElement(root) ?? root;
  final title = feedPlainText(_directChildText(feed, 'title'));
  final entries = <_XmlElement>[
    for (final node in _allElements(document))
      if (node.localName == 'item' || node.localName == 'entry') node,
  ];
  if (entries.isEmpty && !_isFeedRoot(root, feed)) {
    throw const FeedParseException();
  }
  final clock = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  final parsed = <ParsedFeedEntry>[];
  for (var index = 0; index < entries.length && parsed.length < 50; index++) {
    final entry = _parseEntry(entries[index], clock - index);
    if (entry == null) continue;
    parsed.add(entry);
  }
  parsed.sort((a, b) {
    final byDate = b.publishedAt.compareTo(a.publishedAt);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  return ParsedFeed(title: title, entries: parsed);
}

bool _isFeedRoot(_XmlElement root, _XmlElement feed) {
  const names = {'rss', 'feed', 'rdf', 'channel'};
  return names.contains(root.localName) || names.contains(feed.localName);
}

Iterable<_XmlElement> _allElements(_XmlDocument document) sync* {
  for (final element in document.elements) {
    yield element;
    yield* element.descendants;
  }
}

_XmlElement? _feedElement(_XmlElement root) {
  if (root.localName == 'feed' || root.localName == 'channel') return root;
  for (final child in root.elementChildren) {
    if (child.localName == 'channel' || child.localName == 'feed') {
      return child;
    }
  }
  return null;
}

ParsedFeedEntry? _parseEntry(_XmlElement entry, int fallbackDate) {
  final title = feedPlainText(_directChildText(entry, 'title'));
  final link = _entryLink(entry);
  final excerpt = _truncate(feedPlainText(_entryBody(entry)), 4000);
  final idText = _firstNonEmpty([
    _directChildText(entry, 'guid'),
    _directChildText(entry, 'id'),
    link,
    title,
  ]);
  if (idText == null && title.isEmpty && excerpt.isEmpty) return null;
  final published = _entryDate(entry) ?? (fallbackDate < 0 ? 0 : fallbackDate);
  return ParsedFeedEntry(
    id: idText ?? 'item-$fallbackDate',
    title: _truncate(_singleLine(title), 200),
    excerpt: excerpt,
    publishedAt: published,
    link: link,
  );
}

String? _entryLink(_XmlElement entry) {
  String? hrefLink;
  String? textLink;
  for (final child in entry.elementChildren) {
    if (child.localName != 'link') continue;
    final rel = (child.attribute('rel') ?? '').toLowerCase();
    if (rel == 'self' || rel == 'enclosure' || rel == 'replies') continue;
    final href = child.attribute('href')?.trim();
    if (href != null &&
        href.isNotEmpty &&
        (rel.isEmpty || rel == 'alternate') &&
        hrefLink == null) {
      hrefLink = href;
    }
    final text = child.innerText.trim();
    if (text.contains('://') && textLink == null) textLink = text;
  }
  final link = (hrefLink ?? textLink)?.trim();
  if (link == null || link.isEmpty) return null;
  return link;
}

String _entryBody(_XmlElement entry) {
  return _firstNonEmpty([
        _directChildText(entry, 'encoded'),
        _directChildText(entry, 'content'),
        _directChildText(entry, 'description'),
        _directChildText(entry, 'summary'),
      ]) ??
      '';
}

int? _entryDate(_XmlElement entry) {
  for (final name in ['pubDate', 'published', 'updated', 'date']) {
    final raw = _directChildText(entry, name);
    final parsed = parseFeedDate(raw);
    if (parsed != null) return parsed;
  }
  return null;
}

String _directChildText(_XmlElement element, String localName) {
  for (final child in element.elementChildren) {
    if (child.localName == localName.toLowerCase()) return child.innerText;
  }
  return '';
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final text = value?.trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

String _singleLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _truncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  return text.substring(0, maxChars).trimRight();
}

/// Strips tags and decodes the entities that show up in feed titles and
/// descriptions. The result is plain text for the timeline, not HTML.
String feedPlainText(String raw) {
  var text = decodeXmlEntities(raw);
  text = text.replaceAll(
    RegExp(
      r'<(script|style)\b[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = decodeXmlEntities(text);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return text.trim();
}

String decodeXmlEntities(String input) {
  return input.replaceAllMapped(_entityPattern, (match) {
    final token = match.group(1)!;
    switch (token) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'nbsp':
        return ' ';
    }
    if (token.startsWith('#x') || token.startsWith('#X')) {
      final value = int.tryParse(token.substring(2), radix: 16);
      if (value == null || value <= 0) return match.group(0)!;
      return String.fromCharCode(value);
    }
    if (token.startsWith('#')) {
      final value = int.tryParse(token.substring(1));
      if (value == null || value <= 0) return match.group(0)!;
      return String.fromCharCode(value);
    }
    return match.group(0)!;
  });
}

final _entityPattern = RegExp(
  r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);',
);

/// RFC 822 and ISO-8601 instants used by RSS and Atom, as unix seconds.
int? parseFeedDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc().millisecondsSinceEpoch ~/ 1000;
  final match = _rfc822.firstMatch(text);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = _months[match.group(2)!.toLowerCase()];
  final year = int.tryParse(match.group(3)!);
  final hour = int.tryParse(match.group(4)!);
  final minute = int.tryParse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  if (day == null ||
      month == null ||
      year == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  final zone = match.group(7);
  var offsetMinutes = 0;
  if (zone != null &&
      zone.isNotEmpty &&
      !_utcZones.contains(zone.toUpperCase())) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final digits = zone.substring(1);
    if (digits.length < 4) return null;
    final zoneHour = int.tryParse(digits.substring(0, 2)) ?? 0;
    final zoneMinute = int.tryParse(digits.substring(2, 4)) ?? 0;
    offsetMinutes = sign * (zoneHour * 60 + zoneMinute);
  }
  final utc = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
  ).subtract(Duration(minutes: offsetMinutes));
  return utc.millisecondsSinceEpoch ~/ 1000;
}

const _utcZones = {'Z', 'GMT', 'UT', 'UTC'};

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

final _rfc822 = RegExp(
  r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*(Z|GMT|UT|UTC|[+-]\d{4})?$',
  caseSensitive: false,
);

class _XmlDocument {
  _XmlDocument(this.elements);

  final List<_XmlElement> elements;

  _XmlElement? get rootElement {
    for (final element in elements) {
      return element;
    }
    return null;
  }

  static _XmlDocument parse(String source) {
    final parser = _XmlParser(source);
    return _XmlDocument(parser.parseElements());
  }
}

class _XmlElement extends _XmlNode {
  _XmlElement(this.name, this.attributes, this.children);

  final String name;
  final Map<String, String> attributes;
  final List<_XmlNode> children;

  String get localName {
    final colon = name.lastIndexOf(':');
    final local = colon == -1 ? name : name.substring(colon + 1);
    return local.toLowerCase();
  }

  List<_XmlElement> get elementChildren => [
    for (final child in children)
      if (child is _XmlElement) child,
  ];

  Iterable<_XmlElement> get descendants sync* {
    for (final child in elementChildren) {
      yield child;
      yield* child.descendants;
    }
  }

  String? attribute(String localName) {
    final wanted = localName.toLowerCase();
    for (final entry in attributes.entries) {
      final colon = entry.key.lastIndexOf(':');
      final local = colon == -1 ? entry.key : entry.key.substring(colon + 1);
      if (local.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  String get innerText {
    final buffer = StringBuffer();
    for (final child in children) {
      if (child is _XmlText) {
        buffer.write(child.text);
      } else if (child is _XmlElement) {
        buffer.write(child.innerText);
      }
    }
    return buffer.toString();
  }
}

sealed class _XmlNode {}

class _XmlText extends _XmlNode {
  _XmlText(this.text);
  final String text;
}

class _XmlParser {
  _XmlParser(String source) : source = source.replaceFirst('\uFEFF', '') {
    if (this.source.length > _maxChars) {
      this.source = this.source.substring(0, _maxChars);
    }
  }

  static const _maxChars = 2000000;

  String source;
  int index = 0;

  List<_XmlElement> parseElements() {
    final nodes = _parseNodes(depth: 0);
    return [
      for (final node in nodes)
        if (node is _XmlElement) node,
    ];
  }

  List<_XmlNode> _parseNodes({required int depth}) {
    final nodes = <_XmlNode>[];
    while (index < source.length) {
      if (source.startsWith('</', index)) break;
      final next = source.indexOf('<', index);
      if (next == -1) {
        nodes.add(_XmlText(source.substring(index)));
        index = source.length;
        break;
      }
      if (next > index) {
        nodes.add(_XmlText(source.substring(index, next)));
        index = next;
      }
      if (source.startsWith('</', index)) break;
      if (source.startsWith('<!--', index)) {
        final end = source.indexOf('-->', index + 4);
        index = end == -1 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<![CDATA[', index)) {
        final end = source.indexOf(']]>', index + 9);
        final text = end == -1
            ? source.substring(index + 9)
            : source.substring(index + 9, end);
        nodes.add(_XmlText(text));
        index = end == -1 ? source.length : end + 3;
        continue;
      }
      if (source.startsWith('<?', index) || source.startsWith('<!', index)) {
        final end = source.indexOf('>', index + 2);
        index = end == -1 ? source.length : end + 1;
        continue;
      }
      if (depth >= 48) {
        index = source.length;
        break;
      }
      final element = _parseElement(depth);
      if (element != null) nodes.add(element);
    }
    return nodes;
  }

  _XmlElement? _parseElement(int depth) {
    if (index >= source.length || source.codeUnitAt(index) != 0x3C) {
      return null;
    }
    index++;
    final name = _readName();
    if (name.isEmpty) return null;
    final attributes = _readAttributes();
    _skipSpace();
    if (index < source.length && source.startsWith('/>', index)) {
      index += 2;
      return _XmlElement(name, attributes, const []);
    }
    if (index < source.length && source.codeUnitAt(index) == 0x3E) index++;
    final children = _parseNodes(depth: depth + 1);
    if (source.startsWith('</', index)) {
      index += 2;
      _readName();
      final end = source.indexOf('>', index);
      index = end == -1 ? source.length : end + 1;
    }
    return _XmlElement(name, attributes, children);
  }

  Map<String, String> _readAttributes() {
    final attributes = <String, String>{};
    while (index < source.length) {
      _skipSpace();
      if (index >= source.length) break;
      final char = source.codeUnitAt(index);
      if (char == 0x3E || char == 0x2F) break;
      final name = _readName();
      if (name.isEmpty) {
        index++;
        continue;
      }
      _skipSpace();
      if (index >= source.length || source.codeUnitAt(index) != 0x3D) {
        continue;
      }
      index++;
      _skipSpace();
      attributes[name] = _readQuoted();
    }
    return attributes;
  }

  String _readQuoted() {
    if (index >= source.length) return '';
    final quote = source.codeUnitAt(index);
    if (quote != 0x22 && quote != 0x27) return '';
    index++;
    final start = index;
    final end = source.indexOf(String.fromCharCode(quote), index);
    if (end == -1) {
      index = source.length;
      return source.substring(start);
    }
    index = end + 1;
    return decodeXmlEntities(source.substring(start, end));
  }

  String _readName() {
    final start = index;
    while (index < source.length) {
      final char = source.codeUnitAt(index);
      final ok =
          char == 0x3A ||
          char == 0x5F ||
          char == 0x2D ||
          char == 0x2E ||
          (char >= 0x30 && char <= 0x39) ||
          (char >= 0x41 && char <= 0x5A) ||
          (char >= 0x61 && char <= 0x7A);
      if (!ok) break;
      index++;
    }
    return source.substring(start, index);
  }

  void _skipSpace() {
    while (index < source.length) {
      final char = source.codeUnitAt(index);
      if (char != 0x20 && char != 0x09 && char != 0x0A && char != 0x0D) break;
      index++;
    }
  }
}

/// `https://Example.com/feed/` and `example.com/feed` share one subscription.
String? canonicalFeedUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) path = '/';
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '${uri.scheme}://${uri.host.toLowerCase()}$port$path$query';
}
