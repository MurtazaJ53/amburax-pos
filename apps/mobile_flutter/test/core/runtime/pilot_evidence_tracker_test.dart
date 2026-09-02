import 'package:business_hub_mobile/core/runtime/pilot_evidence_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracker starts with all core artifacts missing', () {
    const tracker = PilotEvidenceTrackerState();

    expect(tracker.capturedCoreCount, 0);
    expect(tracker.totalCoreCount, greaterThan(0));
    expect(tracker.isCoreComplete, isFalse);
    expect(
      tracker.missingCoreArtifacts.map((artifact) => artifact.id),
      containsAll(<String>[
        'pilot_snapshot',
        'readiness_signoff',
        'smoke_report',
        'handoff_pack',
        'shift_closeout',
        'rollout_evidence',
      ]),
    );
  });

  test('markCaptured records timestamps and advances core completion', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Bhavnagar wave 1',
          startedAt: DateTime.utc(2026, 5, 2, 7, 45),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 2, 8, 5),
        );

    expect(tracker.capturedCoreCount, 2);
    expect(tracker.latestCapturedArtifact?.id, 'readiness_signoff');
    expect(tracker.latestCapturedAt, DateTime.utc(2026, 5, 2, 8, 5));
    expect(tracker.isCaptured('pilot_snapshot'), isTrue);
    expect(tracker.sessionLabel, 'Bhavnagar wave 1');
  });

  test('markCaptured ignores unknown artifact ids', () {
    final tracker = const PilotEvidenceTrackerState().markCaptured('unknown');

    expect(tracker.capturedAtByArtifact, isEmpty);
  });

  test('toMultilineText includes captured and missing sections', () {
    final tracker = const PilotEvidenceTrackerState()
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .markCaptured(
          'operator_action_brief',
          capturedAt: DateTime.utc(2026, 5, 2, 8, 1),
        );

    final report = tracker.toMultilineText();

    expect(report, contains('Business Hub pilot evidence tracker'));
    expect(report, contains('Pilot snapshot'));
    expect(report, contains('Missing core artifacts:'));
    expect(report, contains('Readiness signoff'));
    expect(report, contains('Missing optional artifacts:'));
  });

  test('state round-trips through json payload', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 1 shift A',
          startedAt: DateTime.utc(2026, 5, 2, 7, 30),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .markCaptured(
          'rollout_evidence',
          capturedAt: DateTime.utc(2026, 5, 2, 9, 30),
        );

    final decoded = PilotEvidenceTrackerState.fromJson(tracker.toJson());

    expect(decoded.capturedCoreCount, tracker.capturedCoreCount);
    expect(decoded.latestCapturedArtifact?.id, 'rollout_evidence');
    expect(decoded.latestCapturedAt, DateTime.utc(2026, 5, 2, 9, 30));
    expect(decoded.sessionLabel, 'Wave 1 shift A');
    expect(decoded.sessionStartedAt, DateTime.utc(2026, 5, 2, 7, 30));
  });

  test('fresh empty session still counts as storable state', () {
    final tracker = const PilotEvidenceTrackerState().startFreshSession(
      sessionLabel: 'Wave 3 shift A',
      startedAt: DateTime.utc(2026, 5, 2, 13),
    );

    expect(tracker.capturedAtByArtifact, isEmpty);
    expect(tracker.hasStoredState, isTrue);
  });

  test('startFreshSession clears captures and stamps a new session window', () {
    final tracker = const PilotEvidenceTrackerState()
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .startFreshSession(
          sessionLabel: 'Wave 2 shift B',
          startedAt: DateTime.utc(2026, 5, 2, 10),
        );

    expect(tracker.capturedAtByArtifact, isEmpty);
    expect(tracker.sessionLabel, 'Wave 2 shift B');
    expect(tracker.sessionStartedAt, DateTime.utc(2026, 5, 2, 10));
    expect(tracker.lastResetAt, DateTime.utc(2026, 5, 2, 10));
  });

  test('startFreshSession archives the previous session summary', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 1 shift A',
          startedAt: DateTime.utc(2026, 5, 2, 7, 30),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 2, 8, 10),
        )
        .startFreshSession(
          sessionLabel: 'Wave 1 shift B',
          startedAt: DateTime.utc(2026, 5, 2, 12),
        );

    expect(tracker.sessionLabel, 'Wave 1 shift B');
    expect(tracker.archivedSessions, hasLength(1));
    expect(tracker.latestArchivedSession?.sessionLabel, 'Wave 1 shift A');
    expect(tracker.latestArchivedSession?.capturedCoreCount, 2);
    expect(
      tracker.latestArchivedSession?.latestCapturedArtifactLabel,
      'Readiness signoff',
    );
  });

  test('tracker text includes archived session summaries', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 1 shift A',
          startedAt: DateTime.utc(2026, 5, 2, 7, 30),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .startFreshSession(
          sessionLabel: 'Wave 1 shift B',
          startedAt: DateTime.utc(2026, 5, 2, 12),
        );

    final report = tracker.toMultilineText();

    expect(report, contains('Archived sessions: 1'));
    expect(report, contains('Wave 1 shift A'));
  });

  test(
    'withoutArchivedSessions preserves active session and clears history',
    () {
      final tracker = const PilotEvidenceTrackerState()
          .ensureSession(
            defaultLabel: 'Wave 1 shift A',
            startedAt: DateTime.utc(2026, 5, 2, 7, 30),
          )
          .markCaptured(
            'pilot_snapshot',
            capturedAt: DateTime.utc(2026, 5, 2, 8),
          )
          .startFreshSession(
            sessionLabel: 'Wave 1 shift B',
            startedAt: DateTime.utc(2026, 5, 2, 12),
          )
          .withoutArchivedSessions();

      expect(tracker.archivedSessions, isEmpty);
      expect(tracker.sessionLabel, 'Wave 1 shift B');
      expect(tracker.hasStoredState, isTrue);
    },
  );

  test('archive pack text includes active and archived sections', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 1 shift A',
          startedAt: DateTime.utc(2026, 5, 2, 7, 30),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .startFreshSession(
          sessionLabel: 'Wave 1 shift B',
          startedAt: DateTime.utc(2026, 5, 2, 12),
        );

    final report = tracker.toArchivePackText();

    expect(report, contains('Business Hub pilot evidence archive pack'));
    expect(report, contains('=== ACTIVE TRACKER ==='));
    expect(report, contains('=== ARCHIVED SESSIONS ==='));
    expect(report, contains('Wave 1 shift A'));
  });

  test('archive insights summarize recent healthy and attention posture', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 1 shift A',
          startedAt: DateTime.utc(2026, 5, 2, 7, 30),
        )
        .markCaptured('pilot_snapshot', capturedAt: DateTime.utc(2026, 5, 2, 8))
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 2, 8, 10),
        )
        .startFreshSession(
          sessionLabel: 'Wave 1 shift B',
          startedAt: DateTime.utc(2026, 5, 2, 12),
        )
        .markCaptured(
          'pilot_snapshot',
          capturedAt: DateTime.utc(2026, 5, 2, 12, 20),
        )
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 2, 12, 25),
        )
        .markCaptured(
          'smoke_report',
          capturedAt: DateTime.utc(2026, 5, 2, 12, 30),
        )
        .markCaptured(
          'handoff_pack',
          capturedAt: DateTime.utc(2026, 5, 2, 12, 35),
        )
        .markCaptured(
          'shift_closeout',
          capturedAt: DateTime.utc(2026, 5, 2, 12, 45),
        )
        .markCaptured(
          'rollout_evidence',
          capturedAt: DateTime.utc(2026, 5, 2, 13),
        )
        .startFreshSession(
          sessionLabel: 'Wave 1 shift C',
          startedAt: DateTime.utc(2026, 5, 2, 16),
        );

    expect(tracker.archivedSessions, hasLength(2));
    expect(tracker.archivedHealthyCount, 1);
    expect(tracker.archivedAttentionCount, 1);
    expect(tracker.archiveTrendLabel, 'Mixed trend');
    expect(
      tracker.archiveInsightSummary,
      '1 healthy / 1 attention across last 2 archived sessions',
    );
    expect(tracker.recentArchiveShowsAttention, isTrue);
  });

  test('archive insights text includes posture and recent archived lines', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 4 shift A',
          startedAt: DateTime.utc(2026, 5, 3, 7),
        )
        .markCaptured(
          'pilot_snapshot',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 5),
        )
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 10),
        )
        .markCaptured(
          'smoke_report',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 15),
        )
        .markCaptured(
          'handoff_pack',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 20),
        )
        .markCaptured(
          'shift_closeout',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 25),
        )
        .markCaptured(
          'rollout_evidence',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 30),
        )
        .startFreshSession(
          sessionLabel: 'Wave 4 shift B',
          startedAt: DateTime.utc(2026, 5, 3, 12),
        );

    final report = tracker.toArchiveInsightsText();

    expect(report, contains('Business Hub pilot evidence archive insights'));
    expect(report, contains('Archive posture: Healthy trend'));
    expect(report, contains('Wave 4 shift A'));
  });
}
