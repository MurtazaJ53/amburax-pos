import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

class SettingsAttendanceScreen extends ConsumerStatefulWidget {
  const SettingsAttendanceScreen({super.key});

  @override
  ConsumerState<SettingsAttendanceScreen> createState() =>
      _SettingsAttendanceScreenState();
}

class _SettingsAttendanceScreenState
    extends ConsumerState<SettingsAttendanceScreen> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _refreshAttendance() async {
    ref.invalidate(attendanceSummaryProvider);
    ref.invalidate(attendanceSessionsProvider);
    await Future.wait<void>(<Future<void>>[
      ref.read(attendanceSummaryProvider.future).then((_) {}),
      ref.read(attendanceSessionsProvider.future).then((_) {}),
    ]);
  }

  Future<bool> _submitAttendance({
    required MobileSession session,
    required String membershipId,
    required String status,
    String note = '',
  }) async {
    if (_busy) {
      return false;
    }

    final now = DateTime.now();
    final normalizedStatus = status.trim().toUpperCase();
    final shouldClockIn =
        normalizedStatus == 'PRESENT' || normalizedStatus == 'HALF_DAY';

    if (!MobileRuntimeConfig.backendSyncEnabled) {
      setState(() {
        _messageIsError = false;
        _message =
            'Attendance needs backend sync because multiple staff devices must share the same roster and shift records. Local mode keeps POS, inventory, customers, and history active.';
      });
      return false;
    }

    setState(() {
      _busy = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      await ref
          .read(backendApiClientProvider)
          .createAttendanceSession(
            user: session.user,
            shopId: session.shopId!,
            membershipId: membershipId,
            sessionDate: DateTime(now.year, now.month, now.day),
            status: normalizedStatus,
            clockInAt: shouldClockIn ? now : null,
            note: note,
          );
      await _refreshAttendance();
      if (!mounted) {
        return true;
      }
      setState(() {
        _messageIsError = false;
        _message = 'Attendance saved for today.';
      });
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _messageIsError = true;
        _message = _friendlyAttendanceError(error.toString());
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openManagerAttendanceSheet({
    required BuildContext context,
    required MobileSession session,
    required List<WorkspaceTeamMemberRecord> members,
  }) async {
    final colors = AppColors.of(context);
    if (!session.hasShop || members.isEmpty) {
      return;
    }

    final allowedMembers = members
        .where((item) => item.status != 'disabled')
        .toList(growable: false);
    if (allowedMembers.isEmpty) {
      return;
    }

    var selectedMembershipId = allowedMembers.first.id;
    var selectedStatus = 'PRESENT';
    final noteController = TextEditingController();
    var saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    const AppSheetHeader(
                      eyebrow: 'Attendance desk',
                      title: 'Mark attendance',
                      subtitle:
                          'Pick a team member, choose todayâ€™s status, and save the shift posture into this workspace.',
                      icon: Icons.fact_check_rounded,
                    ),
                    const SizedBox(height: 16),
                    MobileSheetSection(
                      title: 'Today',
                      child: Column(
                        children: <Widget>[
                          DropdownButtonFormField<String>(
                            initialValue: selectedMembershipId,
                            items: allowedMembers
                                .map(
                                  (member) => DropdownMenuItem<String>(
                                    value: member.id,
                                    child: Text(
                                      '${member.memberName}  ·  ${member.roleLabel}',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedMembershipId = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Member',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedStatus,
                            items: _attendanceStatusChoices
                                .map(
                                  (choice) => DropdownMenuItem<String>(
                                    value: choice.value,
                                    child: Text(choice.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedStatus = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: noteController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Note',
                              hintText:
                                  'Shift comment, leave reason, or handoff note',
                            ),
                          ),
                          if (errorText != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setState(() {
                                        saving = true;
                                        errorText = null;
                                      });
                                      final success = await _submitAttendance(
                                        session: session,
                                        membershipId: selectedMembershipId,
                                        status: selectedStatus,
                                        note: noteController.text.trim(),
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      if (success) {
                                        Navigator.of(context).pop();
                                      } else {
                                        setState(() {
                                          saving = false;
                                          errorText = _message;
                                        });
                                      }
                                    },
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_rounded),
                              label: Text(
                                saving
                                    ? 'Saving attendance'
                                    : 'Save attendance',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final membershipsAsync = ref.watch(shopMembershipsProvider);
    final memberships =
        membershipsAsync.asData?.value ?? const <ShopMembershipAccessRecord>[];
    final teamMembersAsync = ref.watch(workspaceTeamMembersProvider);
    final teamMembers =
        teamMembersAsync.asData?.value ?? const <WorkspaceTeamMemberRecord>[];
    final summaryAsync = ref.watch(attendanceSummaryProvider);
    final summary = summaryAsync.asData?.value;
    final sessionsAsync = ref.watch(attendanceSessionsProvider);
    final sessions =
        sessionsAsync.asData?.value ?? const <AttendanceSessionRecord>[];

    if (session == null) {
      return AppScreen(
        scrollable: false,
        title: 'Attendance',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Loading attendance',
              child: AppEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking workspace access',
                body:
                    'Business Hub is loading the signed-in workspace before opening attendance.',
              ),
            ),
          ],
        ),
      );
    }

    if (!shop.supportsAttendance) {
      return AppScreen(
        scrollable: false,
        title: 'Attendance',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Attendance unlocks on Growth and Pro',
              child: AppEmptyState(
                icon: Icons.workspace_premium_rounded,
                title: 'Attendance is not active on this plan',
                body:
                    'This workspace is on a lighter plan, so staffing stays hidden here until the owner upgrades the shop plan.',
              ),
            ),
          ],
        ),
      );
    }

    final currentMembershipId = _resolveCurrentMembershipId(
      session,
      memberships,
    );
    final today = DateTime.now();
    final todayRecord = currentMembershipId == null
        ? null
        : sessions
              .where((item) => item.membershipId == currentMembershipId)
              .cast<AttendanceSessionRecord?>()
              .firstWhere(
                (item) => item != null && _sameDay(item.sessionDate, today),
                orElse: () => null,
              );

    return AppScreen(
      scrollable: false,
      title: 'Attendance',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: session.isOwnerLike ? 'Attendance desk' : 'My attendance',
            subtitle: session.isOwnerLike
                ? 'Review who is on the floor, mark today for the team, and keep staffing visible without opening a separate HR system.'
                : 'Mark your shift, review your recent attendance, and keep your daily operator access connected to this workspace.',
            icon: Icons.fact_check_rounded,
            accent: AppPalette.primary,
            primaryTag: AppTag(
              label: session.displayRoleLabel,
              icon: Icons.badge_rounded,
              tone: AppTone.success,
            ),
            secondaryTag: AppTag(
              label: todayRecord == null
                  ? 'Unmarked today'
                  : _statusLabel(todayRecord.status).toUpperCase(),
              icon: todayRecord == null
                  ? Icons.event_busy_rounded
                  : Icons.event_available_rounded,
              tone: todayRecord == null ? AppTone.warning : AppTone.success,
            ),
          ),
          const SizedBox(height: 18),
          if (_message != null) ...<Widget>[
            AppPanel(
              title: _messageIsError ? 'Attendance issue' : 'Attendance saved',
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withValues(alpha: 0.76),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          AppPanel(
            title: session.isOwnerLike
                ? 'How staffing works'
                : 'How your access works',
            action: AppTag(
              label: session.isOwnerLike ? 'TEAM READY' : 'STAFF READY',
              icon: session.isOwnerLike
                  ? Icons.groups_rounded
                  : Icons.person_pin_circle_rounded,
              tone: AppTone.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.isOwnerLike
                      ? 'Add the staff member with the exact email they will use on the phone. After that, they can sign in with the same email and mark attendance from Business Hub.'
                      : 'Your owner or store admin must attach this exact email to the workspace first. After that, sign in with the same email and mark your shift here.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (session.isOwnerLike)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          context.push('/settings/team');
                        },
                        icon: const Icon(Icons.groups_rounded),
                        label: const Text('Open workspace team'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _refreshAttendance();
                            },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh attendance'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth > 520 ? 4 : 2;
              return GridView.count(
                crossAxisCount: count,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: constraints.maxWidth < 420 ? 1.45 : 1.02,
                children: <Widget>[
                  AppMetric(
                    label: 'Records',
                    value: Text('${summary?.totalSessions ?? sessions.length}'),
                    caption: 'Attendance sessions visible',
                    icon: Icons.list_alt_rounded,
                    tone: AppTone.primary,
                  ),
                  AppMetric(
                    label: 'Present',
                    value: Text('${summary?.presentCount ?? 0}'),
                    caption: 'Marked present',
                    icon: Icons.check_circle_rounded,
                    tone: AppTone.success,
                  ),
                  AppMetric(
                    label: 'Leave',
                    value: Text('${summary?.leaveCount ?? 0}'),
                    caption: 'Leave sessions',
                    icon: Icons.beach_access_rounded,
                    tone: AppTone.warning,
                  ),
                  AppMetric(
                    label: 'On floor today',
                    value: Text('${summary?.activeWorkersToday ?? 0}'),
                    caption: session.isOwnerLike
                        ? 'Team active today'
                        : 'Active workers today',
                    icon: Icons.groups_rounded,
                    tone: AppTone.info,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: session.isOwnerLike ? 'Mark today' : 'Mark my day',
            action: AppTag(
              label: todayRecord == null ? 'Open' : 'Already marked',
              icon: todayRecord == null
                  ? Icons.edit_calendar_rounded
                  : Icons.verified_rounded,
              tone: todayRecord == null ? AppTone.warning : AppTone.success,
            ),
            child: currentMembershipId == null && !session.isOwnerLike
                ? const AppEmptyState(
                    icon: Icons.sync_problem_rounded,
                    title: 'Your staff link is still missing',
                    body:
                        'Ask the owner or store admin to add this exact email in Workspace team first. Then sign back in and mark attendance from here.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        todayRecord == null
                            ? session.isOwnerLike
                                  ? 'Mark a shift for a team member or quickly log your own day if needed.'
                                  : 'Choose your shift status for today. Business Hub will save it to this workspace immediately.'
                            : 'Today is already marked as ${_statusLabel(todayRecord.status).toLowerCase()}. Open recent sessions below if you need to review the saved note.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black.withValues(alpha: 0.72),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (session.isOwnerLike)
                        FilledButton.tonalIcon(
                          onPressed: _busy
                              ? null
                              : () => _openManagerAttendanceSheet(
                                  context: context,
                                  session: session,
                                  members: teamMembers,
                                ),
                          icon: const Icon(Icons.fact_check_rounded),
                          label: const Text('Mark attendance for team'),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _attendanceStatusChoices
                              .map(
                                (choice) => FilledButton.tonalIcon(
                                  onPressed: _busy || todayRecord != null
                                      ? null
                                      : () => _submitAttendance(
                                          session: session,
                                          membershipId: currentMembershipId!,
                                          status: choice.value,
                                        ),
                                  icon: Icon(choice.icon),
                                  label: Text(choice.shortLabel),
                                ),
                              )
                              .toList(growable: false),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: session.isOwnerLike
                ? 'Recent team sessions'
                : 'My recent sessions',
            action: AppTag(
              label: sessionsAsync.isLoading
                  ? 'Refreshing'
                  : sessions.isEmpty
                  ? 'No records'
                  : '${sessions.length} shown',
              icon: sessionsAsync.isLoading
                  ? Icons.sync_rounded
                  : Icons.receipt_long_rounded,
              tone: AppTone.primary,
            ),
            child: sessionsAsync.isLoading
                ? const AppEmptyState(
                    icon: Icons.sync_rounded,
                    title: 'Refreshing attendance',
                    body:
                        'Business Hub is loading the latest attendance records for this workspace.',
                  )
                : sessions.isEmpty
                ? AppEmptyState(
                    icon: Icons.fact_check_rounded,
                    title: session.isOwnerLike
                        ? 'No attendance sessions yet'
                        : 'You have no attendance records yet',
                    body: session.isOwnerLike
                        ? 'Mark today for the team and the recent staffing view will start filling in here.'
                        : 'Mark your day from the attendance panel above and your recent sessions will start showing here.',
                  )
                : Column(
                    children: sessions
                        .take(8)
                        .map(
                          (record) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AttendanceSessionCard(record: record),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSessionCard extends StatelessWidget {
  const _AttendanceSessionCard({required this.record});

  final AttendanceSessionRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = switch (record.status) {
      'PRESENT' => AppTone.success,
      'HALF_DAY' => AppTone.primary,
      'LEAVE' => AppTone.warning,
      _ => AppTone.danger,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    record.memberName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppTag(
                  label: _statusLabel(record.status).toUpperCase(),
                  icon: Icons.event_available_rounded,
                  tone: accent,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${formatCompactDate(record.sessionDate)}  ·  ${_roleLabel(record.memberRole)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AppTag(
                  label: record.clockInAt == null
                      ? 'No clock-in'
                      : 'In ${_formatTime(record.clockInAt!)}',
                  icon: Icons.login_rounded,
                  tone: AppTone.primary,
                ),
                AppTag(
                  label: record.clockOutAt == null
                      ? 'Open shift'
                      : 'Out ${_formatTime(record.clockOutAt!)}',
                  icon: Icons.logout_rounded,
                  tone: AppTone.warning,
                ),
                if (record.totalHours != null)
                  AppTag(
                    label: '${record.totalHours!.toStringAsFixed(1)} h',
                    icon: Icons.schedule_rounded,
                    tone: AppTone.info,
                  ),
              ],
            ),
            if (record.note.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                record.note,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.70),
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttendanceStatusChoice {
  const _AttendanceStatusChoice({
    required this.value,
    required this.label,
    required this.shortLabel,
    required this.icon,
  });

  final String value;
  final String label;
  final String shortLabel;
  final IconData icon;
}

const List<_AttendanceStatusChoice> _attendanceStatusChoices =
    <_AttendanceStatusChoice>[
      _AttendanceStatusChoice(
        value: 'PRESENT',
        label: 'Present',
        shortLabel: 'Present',
        icon: Icons.check_circle_rounded,
      ),
      _AttendanceStatusChoice(
        value: 'HALF_DAY',
        label: 'Half day',
        shortLabel: 'Half day',
        icon: Icons.timelapse_rounded,
      ),
      _AttendanceStatusChoice(
        value: 'LEAVE',
        label: 'Leave',
        shortLabel: 'Leave',
        icon: Icons.beach_access_rounded,
      ),
      _AttendanceStatusChoice(
        value: 'ABSENT',
        label: 'Absent',
        shortLabel: 'Absent',
        icon: Icons.event_busy_rounded,
      ),
    ];

String? _resolveCurrentMembershipId(
  MobileSession session,
  List<ShopMembershipAccessRecord> memberships,
) {
  if (session.membershipId != null && session.membershipId!.isNotEmpty) {
    return session.membershipId;
  }
  for (final membership in memberships) {
    if (membership.shopId == session.shopId && membership.isActive) {
      return membership.id;
    }
  }
  return null;
}

bool _sameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _statusLabel(String value) {
  switch (value.trim().toUpperCase()) {
    case 'PRESENT':
      return 'Present';
    case 'HALF_DAY':
      return 'Half day';
    case 'LEAVE':
      return 'Leave';
    default:
      return 'Absent';
  }
}

String _roleLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    case 'viewer':
      return 'Viewer';
    default:
      return 'Staff';
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String _friendlyAttendanceError(String raw) {
  final message = raw.trim();
  if (message.toLowerCase().contains('unique') ||
      message.toLowerCase().contains('already exists')) {
    return 'Today is already marked for that person. Review recent sessions below instead of creating a duplicate.';
  }
  return message;
}
