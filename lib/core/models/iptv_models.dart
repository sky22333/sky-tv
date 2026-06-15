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
