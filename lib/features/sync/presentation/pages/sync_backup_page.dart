import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/sync/sync_coordinator.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../authentication/presentation/bloc/auth_cubit.dart';
import '../../../backup_restore/data/backup_restore_service.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../transactions/presentation/bloc/transactions_bloc.dart';

/// Covers `SCR-SYNC-001` (Sync Status & Conflict Resolution) and
/// `SCR-BKP-001` (Encrypted `.pcfo` Backup & Staging-Validated Restore).
class SyncBackupPage extends StatefulWidget {
  const SyncBackupPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<SyncBackupPage> createState() => _SyncBackupPageState();
}

class _SyncBackupPageState extends State<SyncBackupPage> {
  int _tick = 0;
  bool _syncing = false;
  bool _backupBusy = false;
  String? _statusMsg;

  void _reload() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.cloud_sync_outlined,
          title: 'No active profile',
          description: 'Select a profile first.',
        ),
      );
    }

    final sync = GetIt.I<SyncCoordinator>();
    final backup = GetIt.I<BackupRestoreService>();
    final cfo = context.cfoColors;

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: const EnterpriseAppBar(
          title: Text('Sync & Vault Backup'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Cloud Sync'),
              Tab(text: 'Encrypted Backup'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FutureBuilder<SyncQueueSnapshot?>(
              key: ValueKey('sync-$_tick-${profile.id.value}'),
              future: sync
                  .getQueueSnapshot(profile.id)
                  .then((r) => r.valueOrNull),
              builder: (context, snap) {
                final q = snap.data;
                return SingleChildScrollView(
                  padding: EnterprisePageContainer.responsivePadding(context),
                  child: EnterprisePageContainer(
                    maxWidth: AppBreakpoints.maxReadingWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClassicExpandCollapse(
                          expanded: _statusMsg != null,
                          child: _statusMsg != null
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: PressScaleCard(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.sm,
                                    ),
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    child: Text(_statusMsg!),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        StaggeredFadeSlide(
                          index: 0,
                          child: PressScaleCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SectionHeader(
                                  title: 'Outbox Queue',
                                  subtitle: 'Active vault: ${profile.name}',
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _OutboxMetricBox(
                                        label: 'Pending',
                                        count: q?.pendingCount ?? 0,
                                        color: cfo.warning,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: _OutboxMetricBox(
                                        label: 'Synced',
                                        count: q?.syncedCount ?? 0,
                                        color: cfo.success,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _OutboxMetricBox(
                                        label: 'Retries',
                                        count:
                                            (q?.retryableErrorCount ?? 0) +
                                            (q?.permanentErrorCount ?? 0),
                                        color: cfo.transfer,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: _OutboxMetricBox(
                                        label: 'Conflicts',
                                        count: q?.conflictCount ?? 0,
                                        color: cfo.expense,
                                      ),
                                    ),
                                  ],
                                ),
                                if (q?.lastPulledAtUtc != null) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Last pulled: ${UiDateFormatter.shortDayMonthYear(q!.lastPulledAtUtc!)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: cfo.subtleText),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                FilledButton.icon(
                                  onPressed: _syncing
                                      ? null
                                      : () async {
                                          setState(() {
                                            _syncing = true;
                                            _statusMsg = null;
                                          });
                                          final res = await sync
                                              .synchronizeProfile(profile.id);
                                          setState(() {
                                            _syncing = false;
                                            _statusMsg = res.fold(
                                              onSuccess: (s) =>
                                                  'Sync done: ${s.pushedAccepted} accepted, ${s.pushedDuplicates} duplicate replays, ${s.pushedConflicts} conflicts, ${s.pulledChanges} pulled.',
                                              onFailure: (f) => f.message,
                                            );
                                          });
                                          _reload();
                                        },
                                  icon: const Icon(Icons.sync_rounded),
                                  label: Text(
                                    _syncing ? 'Syncing...' : 'Sync Now',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (q != null && q.openConflicts.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          SectionHeader(
                            title: 'Open Conflicts (${q.openConflicts.length})',
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          for (final c in q.openConflicts)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: PressScaleCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${c.entityType} (${c.entityId})',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    const Text(
                                      'Never silently overwritten. Choose whether to re-push your local version or accept the server version.',
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Wrap(
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.xs,
                                      children: [
                                        OutlinedButton(
                                          onPressed: () async {
                                            await sync.resolveConflict(
                                              profileId: profile.id,
                                              conflictId: c.id,
                                              resolution: 'accepted_server',
                                            );
                                            _reload();
                                          },
                                          child: const Text('Accept Server'),
                                        ),
                                        FilledButton(
                                          onPressed: () async {
                                            await sync.resolveConflict(
                                              profileId: profile.id,
                                              conflictId: c.id,
                                              resolution: 'kept_local',
                                            );
                                            _reload();
                                          },
                                          child: const Text('Keep Local'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            SingleChildScrollView(
              padding: EnterprisePageContainer.responsivePadding(context),
              child: EnterprisePageContainer(
                maxWidth: AppBreakpoints.maxReadingWidth,
                child: StaggeredFadeSlide(
                  index: 0,
                  child: PressScaleCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconSquircle(
                              icon: Icons.enhanced_encryption_rounded,
                              iconColor: cfo.success,
                              backgroundColor: cfo.successContainer,
                              size: 48,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Encrypted Local Backup (.pcfo)',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    'PBKDF2 + AES-256-GCM + SHA-256 manifest',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: cfo.subtleText),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Passphrases are never stored on-device or in the cloud. If lost, the encrypted archive cannot be decrypted.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: _backupBusy
                              ? null
                              : () => _exportBackup(context, backup),
                          icon: _backupBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_outline_rounded),
                          label: Text(
                            _backupBusy
                                ? 'Working on encrypted archive...'
                                : 'Export Encrypted Backup (.pcfo)',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _backupBusy
                              ? null
                              : () => _restoreBackup(context, backup),
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Validate & Restore Backup'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup(
    BuildContext context,
    BackupRestoreService backup,
  ) async {
    final pass = await showModernDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(
        title: 'Backup Passphrase',
        subtitle: 'Encrypt your .pcfo backup archive with AES-256-GCM',
        fieldLabel: 'Passphrase (min 8 chars)',
        confirmLabel: 'Encrypt & Export',
        showStrengthBar: true,
        requireConfirmation: true,
      ),
    );
    if (pass == null || pass.isEmpty || !context.mounted) return;

    setState(() => _backupBusy = true);
    try {
      final res = await backup.exportEncryptedBackup(passphrase: pass);
      if (!context.mounted) return;
      if (res.isFailure) {
        showFintechToast(
          context,
          res.failureOrNull!.message,
          tone: FintechToastTone.danger,
        );
        return;
      }

      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'pocket_cfo_backup_$stamp.pcfo'));
      await file.writeAsString(res.valueOrNull!);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Pocket CFO Encrypted Backup ($stamp)',
        ),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup(
    BuildContext context,
    BackupRestoreService backup,
  ) async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty || picked.first.path == null || !context.mounted) {
      return;
    }
    String raw;
    try {
      raw = await File(picked.first.path!).readAsString();
    } catch (_) {
      if (context.mounted) {
        showFintechToast(
          context,
          'Unable to read file. Select a valid UTF-8 .pcfo backup archive.',
          tone: FintechToastTone.danger,
        );
      }
      return;
    }
    if (!context.mounted) return;

    final pass = await showModernDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(
        title: 'Enter Backup Passphrase',
        subtitle: 'Decrypt and verify archive integrity in staging first',
        fieldLabel: 'Passphrase',
        confirmLabel: 'Validate in Staging',
        showStrengthBar: false,
      ),
    );
    if (pass == null || pass.isEmpty || !context.mounted) return;

    setState(() => _backupBusy = true);
    try {
      final previewRes = await backup.validateBackupInStaging(
        rawArchive: raw,
        passphrase: pass,
      );
      if (!context.mounted) return;
      if (previewRes.isFailure) {
        showFintechToast(
          context,
          previewRes.failureOrNull!.message,
          tone: FintechToastTone.danger,
        );
        return;
      }

      final preview = previewRes.valueOrNull!;
      final cfo = context.cfoColors;
      setState(() => _backupBusy = false);
      final confirm = await showModernConfirmDialog(
        context: context,
        title: 'Staging Validation Passed',
        subtitle: 'Archive decrypted & verified before import',
        icon: Icons.verified_user_rounded,
        accent: preview.ledgerBalanced
            ? ModernDialogAccent.success
            : ModernDialogAccent.warning,
        confirmLabel: 'Restore Now',
        canConfirm: preview.ledgerBalanced,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cfo.surfaceTonal,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
              ),
              child: Column(
                children: [
                  _BackupSummaryRow(
                    label: 'Schema',
                    value: 'v${preview.metadata.schemaVersion}',
                  ),
                  const SizedBox(height: 6),
                  _BackupSummaryRow(
                    label: 'Profiles',
                    value: '${preview.profileCount}',
                  ),
                  const SizedBox(height: 6),
                  _BackupSummaryRow(
                    label: 'Accounts',
                    value: '${preview.accountCount}',
                  ),
                  const SizedBox(height: 6),
                  _BackupSummaryRow(
                    label: 'Transactions',
                    value: '${preview.transactionCount}',
                  ),
                  const SizedBox(height: 6),
                  _BackupSummaryRow(
                    label: 'Ledger Reconciled',
                    value: preview.ledgerBalanced ? 'YES' : 'NO',
                    valueColor: preview.ledgerBalanced
                        ? cfo.success
                        : cfo.expense,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Proceed with restoring verified records?',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
            ),
          ],
        ),
      );

      if (confirm == true && context.mounted) {
        setState(() => _backupBusy = true);
        final restored = await backup.restoreVerifiedBackup(
          rawArchive: raw,
          passphrase: pass,
        );
        if (context.mounted) {
          showFintechToast(
            context,
            restored.isSuccess
                ? 'Backup restored and ledger verified.'
                : restored.failureOrNull!.message,
            tone: restored.isSuccess
                ? FintechToastTone.success
                : FintechToastTone.danger,
          );
          final userId = context.read<AuthCubit>().state.user?.id;
          if (userId != null) {
            await context.read<ActiveProfileCubit>().loadProfiles(
              userId: userId,
            );
          }
          if (context.mounted) {
            context.read<DashboardBloc>().add(
              const DashboardRefreshRequested(),
            );
            context.read<TransactionsBloc>().add(
              const TransactionsLoadRequested(),
            );
          }
        }
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }
}

class _OutboxMetricBox extends StatelessWidget {
  const _OutboxMetricBox({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.cfoColors.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.cfoColors.subtleText,
            ),
          ),
          const SizedBox(height: 2),
          ClassicAnimatedCount(
            value: count,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupSummaryRow extends StatelessWidget {
  const _BackupSummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.subtitle,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.showStrengthBar,
    this.requireConfirmation = false,
  });

  final String title;
  final String subtitle;
  final String fieldLabel;
  final String confirmLabel;
  final bool showStrengthBar;
  final bool requireConfirmation;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final len = _passCtrl.text.length;
    final ratio = (len / 14).clamp(0.0, 1.0);
    final strengthColor = len >= 12
        ? cfo.success
        : (len >= 8 ? cfo.warning : cfo.expense);
    final strengthLabel = len == 0
        ? 'Enter passphrase'
        : len >= 12
        ? 'Strong'
        : len >= 8
        ? 'Good'
        : 'Too short';

    return ModernDialogShell(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: Icons.enhanced_encryption_rounded,
      confirmLabel: widget.confirmLabel,
      onConfirm: () {
        final pass = _passCtrl.text;
        if (widget.requireConfirmation) {
          if (pass.length < 8) {
            setState(
              () => _error = 'Passphrase must be at least 8 characters.',
            );
            return;
          }
          if (pass != _confirmCtrl.text) {
            setState(() => _error = 'Passphrases do not match.');
            return;
          }
        } else if (pass.isEmpty) {
          setState(() => _error = 'Enter your backup passphrase.');
          return;
        }
        Navigator.of(context).pop(pass);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.expense,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          FintechTextField(
            label: widget.fieldLabel,
            controller: _passCtrl,
            leadingIcon: Icons.key_rounded,
            obscureText: true,
            enableObscureToggle: true,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (widget.requireConfirmation) ...[
            const SizedBox(height: 10),
            FintechTextField(
              label: 'Confirm Passphrase',
              controller: _confirmCtrl,
              leadingIcon: Icons.verified_user_outlined,
              obscureText: true,
              enableObscureToggle: true,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
          if (widget.showStrengthBar) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AnimatedProgressBar(
                    value: ratio,
                    color: strengthColor,
                    height: 5,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  strengthLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: len == 0 ? cfo.subtleText : strengthColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
