import 'package:dio/dio.dart';

import 'client_version.dart';
import 'upgrade.dart';

/// Sends `X-Client-Version` on every request and records every response's upgrade signal (including
/// the `426` of a refused write) in [tracker]. Add it to each Dio that talks to the server.
class ClientVersionInterceptor extends Interceptor {
  ClientVersionInterceptor(this.tracker);

  final UpgradeTracker tracker;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[ClientVersion.header] = tracker.clientVersion.headerValue;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _record(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) _record(response);
    handler.next(err);
  }

  void _record(Response<dynamic> response) {
    tracker.record(UpgradeSignal.fromResponse(response.statusCode, (name) => response.headers.value(name)));
  }
}

/// True when [error] is the server refusing a write from an outdated app (`426 upgrade_required`).
bool isUpgradeRequired(Object error) => error is DioException && error.response?.statusCode == 426;
