import 'dart:async';

import 'client_version.dart';
import 'policy.dart';

/// What a response says about this app's version.
class UpgradeSignal {
  const UpgradeSignal(this.level, {this.upgradeUrl});

  static const none = UpgradeSignal(UpgradeLevel.none);

  final UpgradeLevel level;
  final Uri? upgradeUrl;

  /// From a response's status and headers; [header] looks a header up case-insensitively.
  factory UpgradeSignal.fromResponse(int? status, String? Function(String name) header) {
    Uri? url() => Uri.tryParse(header(ClientVersion.upgradeUrlHeader) ?? '');
    if (status == 426) return UpgradeSignal(UpgradeLevel.required, upgradeUrl: url());
    final level = switch (header(ClientVersion.upgradeHeader)?.toLowerCase()) {
      'required' => UpgradeLevel.required,
      'recommended' => UpgradeLevel.recommended,
      _ => UpgradeLevel.none,
    };
    return level == UpgradeLevel.none ? none : UpgradeSignal(level, upgradeUrl: url());
  }

  @override
  bool operator ==(Object other) => other is UpgradeSignal && other.level == level && other.upgradeUrl == upgradeUrl;

  @override
  int get hashCode => Object.hash(level, upgradeUrl);

  @override
  String toString() => 'UpgradeSignal(${level.name}, $upgradeUrl)';
}

/// The app's view of the server's verdict: the latest response wins (a response without
/// `X-Client-Upgrade` clears an earlier nudge). Show [UpgradeState.showNudge] as a dismissible banner and
/// [UpgradeState.required] as a persistent one.
class UpgradeTracker {
  UpgradeTracker({
    required this.clientVersion,
    String? dismissedVersion,
    this.onDismiss,
  }) : _dismissedVersion = dismissedVersion;

  final ClientVersion clientVersion;

  /// Persist the dismissed app version (e.g. shared_preferences) so the nudge stays away until the next
  /// release; pass what was persisted as `dismissedVersion` on the next launch.
  final FutureOr<void> Function(String version)? onDismiss;

  String? _dismissedVersion;
  UpgradeSignal _signal = UpgradeSignal.none;
  final _changes = StreamController<UpgradeState>.broadcast();

  UpgradeState get state => UpgradeState(_signal, nudgeDismissed: _dismissedVersion == clientVersion.version);

  Stream<UpgradeState> get changes => _changes.stream;

  /// Record what a response said.
  void record(UpgradeSignal signal) {
    if (signal == _signal) return;
    _signal = signal;
    _changes.add(state);
  }

  /// The user closed the nudge: hide it for this app version.
  Future<void> dismissNudge() async {
    _dismissedVersion = clientVersion.version;
    _changes.add(state);
    await onDismiss?.call(clientVersion.version);
  }

  Future<void> close() => _changes.close();
}

class UpgradeState {
  const UpgradeState(this.signal, {required this.nudgeDismissed});

  final UpgradeSignal signal;
  final bool nudgeDismissed;

  bool get required => signal.level == UpgradeLevel.required;

  bool get showNudge => signal.level == UpgradeLevel.recommended && !nudgeDismissed;

  /// Store link from the server, else [fallback] (the app's own store page).
  Uri upgradeUrl(Uri fallback) => signal.upgradeUrl ?? fallback;
}
