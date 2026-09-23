import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/subscriptions/feed_models.dart';
import 'package:mithka/subscriptions/rss_parser.dart';

void main() {
  test('parses RSS 2.0 items newest first', () {
    final feed = parseRssOrAtom('''
<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Example &amp; Co</title>
    <item>
      <title><![CDATA[Hello <b>world</b>]]></title>
      <link>https://example.com/a</link>
      <guid>a-1</guid>
      <pubDate>Tue, 23 Sep 2026 02:29:00 GMT</pubDate>
      <description><![CDATA[<p>First line</p><p>Second</p>]]></description>
    </item>
    <item>
      <title>Rock &amp; Roll</title>
      <link>https://example.com/b</link>
      <pubDate>Mon, 22 Sep 2026 10:00:00 +0000</pubDate>
      <description>Plain</description>
    </item>
  </channel>
</rss>
''');

    expect(feed.title, 'Example & Co');
    expect(feed.entries, hasLength(2));
    expect(feed.entries.first.title, 'Hello world');
    expect(feed.entries.first.id, 'a-1');
    expect(feed.entries.first.link, 'https://example.com/a');
    expect(feed.entries.first.summary, 'First line');
    expect(feed.entries.first.body, 'First line\n\nSecond');
    expect(
      feed.entries.first.publishedAt,
      DateTime.utc(2026, 9, 23, 2, 29).millisecondsSinceEpoch ~/ 1000,
    );
    expect(feed.entries.last.title, 'Rock & Roll');
    expect(
      feed.entries.last.publishedAt,
      DateTime.utc(2026, 9, 22, 10).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('parses Atom links, html summaries, and offsets', () {
    final feed = parseRssOrAtom('''
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <entry>
    <title type="html">Entry</title>
    <id>urn:1</id>
    <updated>2026-09-23T04:29:00+02:00</updated>
    <link rel="self" href="https://example.com/feed"/>
    <link rel="alternate" href="https://example.com/e"/>
    <summary type="html">&lt;p&gt;Hi&lt;/p&gt;</summary>
  </entry>
</feed>
''');

    expect(feed.title, 'Atom Feed');
    expect(feed.entries.single.id, 'urn:1');
    expect(feed.entries.single.link, 'https://example.com/e');
    expect(feed.entries.single.summary, 'Hi');
    expect(feed.entries.single.body, 'Hi');
    expect(
      feed.entries.single.publishedAt,
      DateTime.utc(2026, 9, 23, 2, 29).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('keeps document order when dates are missing', () {
    final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final feed = parseRssOrAtom('''
<rss><channel><title>Undated</title>
  <item><title>First</title><link>https://example.com/1</link></item>
  <item><title>Second</title><link>https://example.com/2</link></item>
</channel></rss>
''', now: now);

    expect(feed.entries.map((entry) => entry.title), ['First', 'Second']);
    expect(feed.entries.first.publishedAt, now.millisecondsSinceEpoch ~/ 1000);
    expect(
      feed.entries.last.publishedAt,
      now.millisecondsSinceEpoch ~/ 1000 - 1,
    );
  });

  test('rejects a page that is not a feed', () {
    expect(
      () => parseRssOrAtom('<html><body><p>Nope</p></body></html>'),
      throwsA(isA<FeedParseException>()),
    );
  });

  test('accepts an empty channel without inventing items', () {
    final feed = parseRssOrAtom(
      '<rss><channel><title>Quiet</title></channel></rss>',
    );
    expect(feed.title, 'Quiet');
    expect(feed.entries, isEmpty);
  });

  test('keeps a short summary and a paragraph body for a long description', () {
    final readme = List.filled(80, 'readme').join(' ');
    final feed = parseRssOrAtom('''
<rss><channel><title>Trending</title>
  <item>
    <title>org/repo</title>
    <link>https://github.com/org/repo</link>
    <description><![CDATA[
      <p>A framework for building agentic apps.</p>
      <p><a href="https://example.com">https://example.com</a></p>
      <hr>
      <h1>Readme</h1>
      <p>First section explains the tool.</p>
      <ul>
        <li>Alpha feature</li>
        <li>Beta feature</li>
      </ul>
      <p>$readme</p>
    ]]></description>
  </item>
  <item>
    <title>Split fields</title>
    <link>https://example.com/split</link>
    <description><![CDATA[<p>Card blurb from the description.</p>]]></description>
    <content:encoded><![CDATA[
      <p>Card blurb from the description.</p>
      <p>The encoded article continues here.</p>
    ]]></content:encoded>
  </item>
</channel></rss>
''');

    final trending = feed.entries.firstWhere(
      (entry) => entry.title == 'org/repo',
    );
    expect(trending.summary, 'A framework for building agentic apps.');
    expect(trending.summary.length, lessThanOrEqualTo(feedSummaryMaxChars));
    expect(trending.summary.contains('Alpha feature'), isFalse);
    expect(trending.body, contains('First section explains the tool.'));
    expect(trending.body, contains('\n\n'));
    expect(trending.body, contains('• Alpha feature'));
    expect(trending.body, contains('• Beta feature'));
    expect(trending.body, contains('Readme'));
    expect(trending.body.length, lessThanOrEqualTo(feedBodyMaxChars));

    final split = feed.entries.firstWhere(
      (entry) => entry.title == 'Split fields',
    );
    expect(split.summary, 'Card blurb from the description.');
    expect(split.body, contains('The encoded article continues here.'));
    expect(split.body, contains('\n\n'));
  });

  test('canonicalizes feed URLs', () {
    expect(
      canonicalFeedUrl('HTTPS://Example.com/feed/'),
      'https://example.com/feed',
    );
    expect(canonicalFeedUrl('example.com/feed'), 'https://example.com/feed');
    expect(canonicalFeedUrl('ftp://example.com/feed'), isNull);
    expect(canonicalFeedUrl(''), isNull);
  });
}
