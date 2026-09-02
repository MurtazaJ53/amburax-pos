import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_runtime_info.dart';

/// Latest available version, provided at build time. Wire this to a small
/// remote JSON endpoint later; for now it is configurable via:
///   --dart-define BUSINESS_HUB_LATEST_VERSION=1.4.0
const String _latestVersion = String.fromEnvironment(
  'BUSINESS_HUB_LATEST_VERSION',
  defaultValue: '',
);

class UpdateStatus {
  const UpdateStatus({
    required this.updateAvailable,
    required this.latestVersion,
  });

  final bool updateAvailable;
  final String latestVersion;

  static const none = UpdateStatus(updateAvailable: false, latestVersion: '');
}

List<int> _parts(String v) => v
    .split('.')
    .map(
      (p) => int.tryParse(RegExp(r'\d+').firstMatch(p)?.group(0) ?? '0') ?? 0,
    )
    .toList(growable: false);

/// Returns > 0 when [a] is newer than [b].
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

final updateStatusProvider = Provider<UpdateStatus>((ref) {
  final current =
      ref.watch(appRuntimeInfoProvider).asData?.value.versionLabel ?? '';
  if (_latestVersion.isEmpty || current.isEmpty) return UpdateStatus.none;
  return UpdateStatus(
    updateAvailable: compareVersions(_latestVersion, current) > 0,
    latestVersion: _latestVersion,
  );
});
