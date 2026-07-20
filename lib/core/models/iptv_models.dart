class IptvSubscription {
  const IptvSubscription({
    required this.id,
    required this.name,
    required this.url,
    required this.enabled,
    this.contentHash = '',
    this.lastCheckedAt,
    this.lastUpdatedAt,
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final String contentHash;
  final DateTime? lastCheckedAt;
  final DateTime? lastUpdatedAt;
}

class IptvChannel {
  const IptvChannel({
    required this.id,
    required this.subscriptionId,
    required this.name,
    required this.url,
    required this.sortOrder,
    this.group,
    this.logo,
    this.tvgId,
    this.tvgName,
  });

  final String id;
  final String subscriptionId;
  final String name;
  final String url;
  final String? group;
  final String? logo;
  final String? tvgId;
  final String? tvgName;
  final int sortOrder;
}

List<IptvChannel> filterIptvChannels(
  List<IptvChannel> channels, {
  String? group,
  String keyword = '',
}) {
  if (group == null && keyword.isEmpty) {
    return channels;
  }
  return channels.where((channel) {
    final matchesGroup = group == null || channel.group == group;
    final matchesKeyword = keyword.isEmpty || channel.name.contains(keyword);
    return matchesGroup && matchesKeyword;
  }).toList();
}

class IptvLibrary {
  const IptvLibrary({
    required this.subscriptions,
    required this.channels,
    required this.groups,
  });

  final List<IptvSubscription> subscriptions;
  final List<IptvChannel> channels;
  final List<String> groups;
}

class IptvImportResult {
  const IptvImportResult({required this.channels, required this.errors});

  final int channels;
  final List<String> errors;
}
