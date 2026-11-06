import 'package:client_version/client_version.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  const version = ClientVersion(app: 'omumu-pod', version: '1.3.0', build: '40', platform: 'ios');

  test('headerValue round-trips and of() sanitises', () {
    expect(version.headerValue, 'omumu-pod/1.3.0+40 (ios)');
    expect(ClientVersion.parse(version.headerValue), version);
    expect(ClientVersion.of(app: 'a', version: '1.0.0-beta', build: '', platform: 'ios').headerValue, 'a/0 (ios)');
  });

  test('UpgradeSignal from a response', () {
    String? Function(String) headers(Map<String, String> h) => (n) => h[n];
    expect(UpgradeSignal.fromResponse(200, headers({})), UpgradeSignal.none);
    expect(
      UpgradeSignal.fromResponse(200, headers({'X-Client-Upgrade': 'recommended', 'X-Upgrade-URL': 'https://s'})),
      UpgradeSignal(UpgradeLevel.recommended, upgradeUrl: Uri.parse('https://s')),
    );
    expect(UpgradeSignal.fromResponse(426, headers({})).level, UpgradeLevel.required);
    expect(UpgradeSignal.fromResponse(200, headers({'X-Client-Upgrade': 'bogus'})), UpgradeSignal.none);
  });

  test('tracker: latest response wins, dismissal is per app version', () async {
    String? persisted;
    final tracker = UpgradeTracker(clientVersion: version, onDismiss: (v) => persisted = v);
    tracker.record(const UpgradeSignal(UpgradeLevel.recommended));
    expect(tracker.state.showNudge, isTrue);
    await tracker.dismissNudge();
    expect(tracker.state.showNudge, isFalse);
    expect(persisted, '1.3.0');
    tracker.record(const UpgradeSignal(UpgradeLevel.required));
    expect(tracker.state.required, isTrue);
    tracker.record(UpgradeSignal.none);
    expect(tracker.state.required, isFalse);

    final nextRelease = UpgradeTracker(
      clientVersion: const ClientVersion(app: 'omumu-pod', version: '1.4.0', platform: 'ios'),
      dismissedVersion: persisted,
    )..record(const UpgradeSignal(UpgradeLevel.recommended));
    expect(nextRelease.state.showNudge, isTrue);
  });

  test('Dio interceptor sends the header and records responses, including 426', () async {
    final tracker = UpgradeTracker(clientVersion: version);
    final sent = <String?>[];
    var reply = (200, <String, List<String>>{'x-client-upgrade': ['recommended']});
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        sent.add(options.headers[ClientVersion.header] as String?);
        return ResponseBody.fromString('{}', reply.$1, headers: reply.$2);
      })
      ..interceptors.add(ClientVersionInterceptor(tracker));

    await dio.get<dynamic>('https://x/api');
    expect(sent.single, 'omumu-pod/1.3.0+40 (ios)');
    expect(tracker.state.signal.level, UpgradeLevel.recommended);

    reply = (426, {'x-client-upgrade': ['required'], 'x-upgrade-url': ['https://store']});
    await expectLater(dio.put<dynamic>('https://x/api'), throwsA(predicate(isUpgradeRequired)));
    expect(tracker.state.required, isTrue);
    expect(tracker.state.upgradeUrl(Uri.parse('https://fallback')), Uri.parse('https://store'));
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      respond(options);

  @override
  void close({bool force = false}) {}
}
