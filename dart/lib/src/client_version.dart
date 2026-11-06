/// `<app>/<version>[+<build>] (<platform>)`, e.g. `omumu-pod/1.2.0+42 (ios)`.
class ClientVersion {
  const ClientVersion({required this.app, required this.version, this.build, required this.platform});

  static const header = 'X-Client-Version';
  static const queryParameter = 'client_version';
  static const upgradeHeader = 'X-Client-Upgrade';
  static const upgradeUrlHeader = 'X-Upgrade-URL';
  static const upgradeRequiredMessage = 'This version of the app is no longer supported. Please update.';

  final String app;
  final String version;
  final String? build;
  final String platform;

  static final _pattern = RegExp(r'^([a-z][a-z0-9-]*)/(\d+(?:\.\d+){0,3})(?:\+([0-9A-Za-z.-]+))?\s+\(([a-z][a-z0-9-]*)\)$');
  static final _version = RegExp(r'^\d+(?:\.\d+){0,3}$');
  static final _build = RegExp(r'^[0-9A-Za-z.-]+$');

  /// From an app's own version and build (e.g. `package_info_plus`'s `version` and `buildNumber`).
  /// An invalid version becomes `0` and an invalid or empty build is dropped, so the header always parses.
  factory ClientVersion.of({required String app, required String version, String? build, required String platform}) =>
      ClientVersion(
        app: app,
        version: _version.hasMatch(version) ? version : '0',
        build: build != null && _build.hasMatch(build) ? build : null,
        platform: platform,
      );

  String get headerValue => '$app/$version${build == null ? '' : '+$build'} ($platform)';

  /// Parses an `X-Client-Version` value; `null` when missing or malformed (an unknown client).
  static ClientVersion? parse(String? value) {
    if (value == null) return null;
    final m = _pattern.firstMatch(value.trim());
    if (m == null) return null;
    return ClientVersion(app: m[1]!, version: m[2]!, build: m[3], platform: m[4]!);
  }

  /// Numeric, component-wise comparison; missing components are 0. Returns -1, 0 or 1.
  static int compare(String a, String b) {
    if (!_version.hasMatch(a)) throw FormatException('not a version', a);
    if (!_version.hasMatch(b)) throw FormatException('not a version', b);
    final pa = a.split('.').map(int.parse).toList();
    final pb = b.split('.').map(int.parse).toList();
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  /// True when [client] is at least [version]; an unknown client counts as current.
  static bool atLeast(ClientVersion? client, String version) => client == null || compare(client.version, version) >= 0;

  @override
  bool operator ==(Object other) =>
      other is ClientVersion &&
      other.app == app &&
      other.version == version &&
      other.build == build &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(app, version, build, platform);

  @override
  String toString() => headerValue;
}
