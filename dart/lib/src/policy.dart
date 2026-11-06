import 'client_version.dart';

enum UpgradeLevel { none, recommended, required }

/// One app and platform's thresholds (server side).
class PolicyEntry {
  const PolicyEntry({required this.app, required this.platform, this.minimum, this.recommended, this.upgradeUrl});

  final String app;
  final String platform;

  /// Oldest version still allowed to write.
  final String? minimum;

  /// Oldest version that is not nudged.
  final String? recommended;
  final String? upgradeUrl;
}

class Evaluation {
  const Evaluation({required this.level, required this.refuse, required this.headers, this.body, this.client});

  final UpgradeLevel level;

  /// True when the request must be answered with `426`.
  final bool refuse;
  final Map<String, String> headers;
  final Map<String, String>? body;
  final ClientVersion? client;
}

const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

(UpgradeLevel, PolicyEntry?) upgradeLevel(List<PolicyEntry> policy, ClientVersion? client) {
  if (client == null) return (UpgradeLevel.none, null);
  final entry = policy.where((e) => e.app == client.app && e.platform == client.platform).firstOrNull;
  if (entry == null) return (UpgradeLevel.none, null);
  if (entry.minimum != null && ClientVersion.compare(client.version, entry.minimum!) < 0) {
    return (UpgradeLevel.required, entry);
  }
  if (entry.recommended != null && ClientVersion.compare(client.version, entry.recommended!) < 0) {
    return (UpgradeLevel.recommended, entry);
  }
  return (UpgradeLevel.none, entry);
}

/// Evaluates a request's `X-Client-Version` and method against [policy] (SPEC.md, Evaluation and Response).
Evaluation evaluate(List<PolicyEntry> policy, String? clientVersion, String method) {
  final client = ClientVersion.parse(clientVersion);
  final (level, entry) = upgradeLevel(policy, client);
  if (level == UpgradeLevel.none) return Evaluation(level: level, refuse: false, headers: const {}, client: client);
  final headers = {
    ClientVersion.upgradeHeader: level.name,
    if (entry?.upgradeUrl != null) ClientVersion.upgradeUrlHeader: entry!.upgradeUrl!,
  };
  final refuse = level == UpgradeLevel.required && !_safeMethods.contains(method.toUpperCase());
  if (!refuse) return Evaluation(level: level, refuse: false, headers: headers, client: client);
  return Evaluation(
    level: level,
    refuse: true,
    headers: headers,
    client: client,
    body: {
      'error': 'upgrade_required',
      'message': ClientVersion.upgradeRequiredMessage,
      if (entry?.upgradeUrl != null) 'upgradeUrl': entry!.upgradeUrl!,
    },
  );
}
