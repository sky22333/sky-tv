import 'package:skytv/core/parser/iptv_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses m3u channels with metadata', () {
    final channels = parseIptvChannels('''
#EXTM3U x-tvg-url="https://example.com/epg.xml"
#EXTINF:-1 tvg-name="CCTV1" tvg-logo="https://example.com/cctv1.png" tvg-id="CCTV1" group-title="央视频道",CCTV-1 综合
http://example.com/cctv1.m3u8
#EXTINF:-1 group-title="卫视频道",湖南卫视
https://example.com/hunan.m3u8
''', 'sub');

    expect(channels, hasLength(2));
    expect(channels.first.name, 'CCTV1');
    expect(channels.first.group, '央视频道');
    expect(channels.first.logo, 'https://example.com/cctv1.png');
    expect(channels.first.tvgId, 'CCTV1');
    expect(channels.last.name, '湖南卫视');
    expect(channels.last.group, '卫视频道');
  });

  test('parses txt channels and genre lines', () {
    final channels = parseIptvChannels('''
央视频道,#genre#
CCTV1,http://example.com/cctv1.m3u8
CCTV2,http://example.com/cctv2.m3u8
卫视频道,#genre#
湖南卫视,http://example.com/hunan.m3u8
''', 'sub');

    expect(channels, hasLength(3));
    expect(channels[0].group, '央视频道');
    expect(channels[1].group, '央视频道');
    expect(channels[2].group, '卫视频道');
  });
}
