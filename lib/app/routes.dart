class SkyRoutes {
  const SkyRoutes._();

  static String detail(String sourceId, String mediaId) {
    return _path('detail', sourceId, mediaId);
  }

  static String category(String sourceId, String categoryId) {
    return _path('category', sourceId, categoryId);
  }

  static String player(
    String sourceId,
    String mediaId, {
    required int lineIndex,
    required int episodeIndex,
    bool resume = false,
  }) {
    final query = <String, String>{
      'line': '$lineIndex',
      'episode': '$episodeIndex',
      if (resume) 'resume': '1',
    };
    final path = _path('player', sourceId, mediaId);
    final queryString = Uri(queryParameters: query).query;
    return '$path?$queryString';
  }

  static String live(String channelId) {
    return '/live/${Uri.encodeComponent(channelId)}';
  }

  static String _path(String first, String second, String third) {
    return '/${[first, second, third].map(Uri.encodeComponent).join('/')}';
  }
}
