import 'dart:convert';
import 'dart:io';

import 'package:client_version/client_version.dart';
import 'package:test/test.dart';

/// Runs the shared conformance fixture (../cases.json).
void main() {
  final cases = jsonDecode(File('../cases.json').readAsStringSync()) as Map<String, dynamic>;

  group('parse', () {
    for (final c in cases['parse'] as List) {
      test(jsonEncode(c['input']), () {
        final e = c['expected'] as Map<String, dynamic>?;
        expect(
          ClientVersion.parse(c['input'] as String?),
          e == null
              ? isNull
              : ClientVersion(
                  app: e['app'] as String,
                  version: e['version'] as String,
                  build: e['build'] as String?,
                  platform: e['platform'] as String,
                ),
        );
      });
    }
  });

  group('compare', () {
    for (final c in cases['compare'] as List) {
      test('${c['a']} ${c['b']}', () {
        expect(ClientVersion.compare(c['a'] as String, c['b'] as String), c['expected']);
        expect(ClientVersion.compare(c['b'] as String, c['a'] as String), -(c['expected'] as int));
      });
    }
  });

  group('evaluate', () {
    for (final c in cases['evaluate'] as List) {
      test(c['name'] as String, () {
        final policy = [
          for (final p in c['policy'] as List)
            PolicyEntry(
              app: p['app'] as String,
              platform: p['platform'] as String,
              minimum: p['minimum'] as String?,
              recommended: p['recommended'] as String?,
              upgradeUrl: p['upgradeUrl'] as String?,
            ),
        ];
        final e = c['expected'] as Map<String, dynamic>;
        final r = evaluate(policy, c['clientVersion'] as String?, c['method'] as String);
        expect(r.level.name, e['level']);
        expect(r.refuse, e['refuse']);
        expect(r.headers, e['headers']);
        if (r.refuse) expect(r.body, e['body']);
      });
    }
  });

  group('atLeast', () {
    for (final c in cases['atLeast'] as List) {
      test('${c['clientVersion']} >= ${c['version']}', () {
        expect(ClientVersion.atLeast(ClientVersion.parse(c['clientVersion'] as String?), c['version'] as String), c['expected']);
      });
    }
  });
}
