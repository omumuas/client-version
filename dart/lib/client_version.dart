/// Client version protocol (SPEC.md in github.com/omumuas/client-version): the `X-Client-Version` value
/// an app sends, version comparison, policy evaluation, the server's upgrade signal, and a Dio
/// interceptor that sends the one and tracks the other.
library;

export 'src/client_version.dart';
export 'src/policy.dart';
export 'src/upgrade.dart';
export 'src/dio_interceptor.dart';
