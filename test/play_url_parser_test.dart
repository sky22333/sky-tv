import 'package:skytv/core/parser/play_url_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses MacCMS multi line play urls', () {
    final lines = parsePlayLines(
      r'线路A$$$线路B',
      r'第1集$https://a.test/1.m3u8#第2集$https://a.test/2.m3u8$$$正片$https://b.test/movie.mp4',
    );

    expect(lines, hasLength(2));
    expect(lines[0].name, '线路A');
    expect(lines[0].episodes, hasLength(2));
    expect(lines[1].episodes.single.url, 'https://b.test/movie.mp4');
  });

  test('drops non http play urls', () {
    final lines = parsePlayLines(
      '线路',
      r'无效$ftp://example.com/1.m3u8#有效$https://example.com/2.m3u8',
    );

    expect(lines, hasLength(1));
    expect(lines.single.episodes, hasLength(1));
    expect(lines.single.episodes.single.title, '有效');
  });
}
