import 'package:skytv/core/parser/source_importer.dart';
import 'package:skytv/core/source/source_id.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes api url and builds stable source id', () {
    final apiUrl = normalizeApiUrl('https://example.com/api.php/provide/vod/');

    expect(apiUrl, 'https://example.com/api.php/provide/vod/at/json');
    expect(buildSourceId('示例', apiUrl), buildSourceId('示例', apiUrl));
  });

  test('imports array sources and deduplicates by generated source id', () {
    final result = importSourcesFromJson('''
      [
        {"name":"示例","api_url":"https://example.com/api.php/provide/vod"},
        {"name":"示例","api_url":"https://example.com/api.php/provide/vod/at/json"}
      ]
    ''');

    expect(result.errors, isEmpty);
    expect(result.sources, hasLength(1));
    expect(result.sources.single.apiUrl, endsWith('/at/json'));
  });

  test('collects item errors without dropping valid sources', () {
    final result = importSourcesFromJson('''
      {
        "sources": [
          {"name":"可用","api_url":"https://example.com/api.php/provide/vod"},
          {"name":"","api_url":"https://bad.example.com"}
        ]
      }
    ''');

    expect(result.sources, hasLength(1));
    expect(result.errors, hasLength(1));
  });
}
