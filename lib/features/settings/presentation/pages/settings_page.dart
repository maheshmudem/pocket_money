import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/environment_config.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/logging/redacting_logger.dart';
import '../../../../core/security/key_manager.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../authentication/presentation/bloc/auth_cubit.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../security_lock/presentation/bloc/app_lock_cubit.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../bloc/settings_cubit.dart';

/// Covers `SCR-SET-001` (Preferences, Theme, Diagnostics, Ledger Self-Check)
/// and `SCR-SET-002` (Security, Biometric/PIN App Lock, Privacy Curtain, Device/Sessions).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static String _formatWholeAmount(int minorUnits, String currencyCode) {
    final factor = CurrencyCatalog.byCode(currencyCode)?.minorFactor ?? 100;
    final whole = (minorUnits / factor).round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final posFromEnd = whole.length - i;
      if (i > 0 && posFromEnd % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final lock = context.watch<AppLockCubit>().state;
    final auth = context.watch<AuthCubit>().state;
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final env = GetIt.I<EnvironmentConfig>();
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final ccy = profile?.baseCurrencyCode ?? 'INR';
    final themeLabel = switch (settings.themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Auto',
    };

    return Scaffold(
      appBar: const EnterpriseAppBar(title: Text('Settings & Security')),
      body: SingleChildScrollView(
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 32),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxReadingWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 0. Flagship Vault Security & Privacy Posture Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechSignatureHero(
                  tone: lock.isEnabled
                      ? SignatureHeroTone.emerald
                      : SignatureHeroTone.indigo,
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Icon(
                          lock.isEnabled
                              ? Icons.verified_user_rounded
                              : Icons.shield_outlined,
                          size: 22,
                          color: lock.isEnabled
                              ? const Color(0xFF34D399)
                              : const Color(0xFF93C5FD),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lock.isEnabled
                                  ? 'Vault Shield Fortified'
                                  : 'AES-256 Encrypted Vault',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${profile?.name ?? 'Local Vault'} • Theme $themeLabel • ${lock.isEnabled ? 'Lock ON' : 'AES-256'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.74),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      HeroGlassPill(
                        label: 'v${env.appVersion}',
                        dotColor: const Color(0xFF34D399),
                        foreground: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 1. Single Canonical Home for Appearance, Theme & Privacy
              const SectionHeader(title: 'Appearance & Privacy'),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 0,
                child: PressScaleCard(
                  key: const Key('settings_appearance_card'),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                AnimatedSwitcher(
                                  duration: AppMotion.resolve(
                                    context,
                                    AppMotion.standard,
                                  ),
                                  switchInCurve: AppMotion.curveEmphasized,
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: RotationTransition(
                                          turns: Tween<double>(
                                            begin: 0.88,
                                            end: 1.0,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                  child: IconSquircle(
                                    key: ValueKey<Brightness>(
                                      Theme.of(context).brightness,
                                    ),
                                    icon:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    iconColor: scheme.primary,
                                    backgroundColor: scheme.primaryContainer,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'App Theme',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.1,
                                            ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Daylight Light, Obsidian Dark or Auto',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FintechStatusPill(
                                  label: themeLabel,
                                  foreground: scheme.primary,
                                  background: scheme.primaryContainer,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FintechThemeModePicker(
                              selectedMode: settings.themeMode,
                              onChanged: (mode) {
                                HapticFeedback.selectionClick();
                                context.read<SettingsCubit>().setThemeMode(
                                  mode,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: settings.hideBalances
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        iconColor: cfo.transfer,
                        iconBackground: cfo.transferContainer,
                        title: 'Mask Balances',
                        subtitle: 'Hide currency amounts across screens',
                        value: settings.hideBalances,
                        onChanged: (_) {
                          HapticFeedback.selectionClick();
                          context.read<SettingsCubit>().toggleHideBalances();
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: Icons.shield_outlined,
                        iconColor: cfo.success,
                        iconBackground: cfo.successContainer,
                        title: 'Privacy Shield',
                        subtitle: 'Hide preview in recent-app switcher',
                        value: settings.privacyCurtainEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context.read<SettingsCubit>().setPrivacyCurtain(v);
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        key: const Key('settings_block_screenshots_switch'),
                        icon: settings.blockScreenshotsEnabled
                            ? Icons.phonelink_lock_rounded
                            : Icons.screenshot_outlined,
                        iconColor: settings.blockScreenshotsEnabled
                            ? scheme.primary
                            : cfo.warning,
                        iconBackground: settings.blockScreenshotsEnabled
                            ? scheme.primaryContainer
                            : cfo.warningContainer,
                        title: 'Block Screenshots & Recording',
                        subtitle: settings.blockScreenshotsEnabled
                            ? 'Screenshots, recording & casting blocked'
                            : 'Allowed • Use Mask Balances to hide amounts',
                        value: settings.blockScreenshotsEnabled,
                        onChanged: (v) =>
                            _handleBlockScreenshotsToggle(context, v, lock),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Smart Alerts & Local Notifications
              const SectionHeader(
                title: 'Smart Alerts & Notifications',
                subtitle: 'Limit warnings, low-balance guard & milestones',
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  key: const Key('settings_smart_alerts_section'),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FintechSwitchRow(
                        key: const Key('settings_notifications_master_switch'),
                        icon: Icons.notifications_active_outlined,
                        iconColor: scheme.primary,
                        iconBackground: scheme.primaryContainer,
                        title: 'Local Notifications',
                        subtitle: 'Heads-up alerts with privacy masking',
                        value: settings.notificationsEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context.read<SettingsCubit>().setNotificationsEnabled(
                            v,
                          );
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: Icons.pie_chart_outline_rounded,
                        iconColor: cfo.expense,
                        iconBackground: cfo.expenseContainer,
                        title: 'Budget Limit Alerts',
                        subtitle: 'Notify at 80% & 100% of budget caps',
                        value: settings.budgetAlertsEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context.read<SettingsCubit>().setBudgetAlertsEnabled(
                            v,
                          );
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: cfo.warning,
                        iconBackground: cfo.warningContainer,
                        title: 'Low Balance Guard',
                        subtitle:
                            'Warn at or below $ccy ${_formatWholeAmount(settings.lowBalanceThresholdMinor, ccy)}',
                        value: settings.lowBalanceAlertsEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context
                              .read<SettingsCubit>()
                              .setLowBalanceAlertsEnabled(v);
                        },
                        bottomChild: settings.lowBalanceAlertsEnabled
                            ? Builder(
                                builder: (context) {
                                  final factor =
                                      CurrencyCatalog.byCode(
                                        ccy,
                                      )?.minorFactor ??
                                      100;
                                  final presets = [
                                    (500 * factor, '500'),
                                    (1000 * factor, '1,000'),
                                    (5000 * factor, '5,000'),
                                  ];
                                  final isCustom = !presets.any(
                                    (p) =>
                                        p.$1 ==
                                        settings.lowBalanceThresholdMinor,
                                  );
                                  return Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: cfo.surfaceTonal,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd,
                                      ),
                                      border: Border.all(color: cfo.divider),
                                    ),
                                    child: Row(
                                      children: [
                                        for (final (i, preset)
                                            in presets.indexed) ...[
                                          if (i > 0) const SizedBox(width: 4),
                                          Expanded(
                                            child: Builder(
                                              builder: (context) {
                                                final selected =
                                                    settings
                                                        .lowBalanceThresholdMinor ==
                                                    preset.$1;
                                                return Material(
                                                  color: selected
                                                      ? scheme.primaryContainer
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppSpacing.radiusSm,
                                                      ),
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          AppSpacing.radiusSm,
                                                        ),
                                                    onTap: () {
                                                      HapticFeedback.selectionClick();
                                                      context
                                                          .read<SettingsCubit>()
                                                          .setLowBalanceThresholdMinor(
                                                            preset.$1,
                                                          );
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 7,
                                                            horizontal: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              AppSpacing
                                                                  .radiusSm,
                                                            ),
                                                        border: selected
                                                            ? Border.all(
                                                                color: scheme
                                                                    .primary,
                                                              )
                                                            : null,
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          '$ccy ${preset.$2}',
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                                color: selected
                                                                    ? scheme
                                                                          .onPrimaryContainer
                                                                    : cfo.subtleText,
                                                                fontWeight:
                                                                    selected
                                                                    ? FontWeight
                                                                          .w800
                                                                    : FontWeight
                                                                          .w600,
                                                                fontFeatures:
                                                                    const [
                                                                      FontFeature.tabularFigures(),
                                                                    ],
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Material(
                                            color: isCustom
                                                ? scheme.primaryContainer
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusSm,
                                            ),
                                            child: InkWell(
                                              key: const Key(
                                                'settings_low_balance_custom_btn',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppSpacing.radiusSm,
                                                  ),
                                              onTap: () =>
                                                  _openCustomLowBalanceDialog(
                                                    context,
                                                    ccy,
                                                    factor,
                                                    settings
                                                        .lowBalanceThresholdMinor,
                                                  ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 7,
                                                      horizontal: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppSpacing.radiusSm,
                                                      ),
                                                  border: isCustom
                                                      ? Border.all(
                                                          color: scheme.primary,
                                                        )
                                                      : null,
                                                ),
                                                alignment: Alignment.center,
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    'Custom',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: isCustom
                                                              ? scheme
                                                                    .onPrimaryContainer
                                                              : cfo.subtleText,
                                                          fontWeight: isCustom
                                                              ? FontWeight.w800
                                                              : FontWeight.w600,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : null,
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: Icons.emoji_events_outlined,
                        iconColor: cfo.income,
                        iconBackground: cfo.incomeContainer,
                        title: 'Goal Milestones',
                        subtitle: 'Celebrate 50% & 100% savings targets',
                        value: settings.goalMilestoneAlertsEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context
                              .read<SettingsCubit>()
                              .setGoalMilestoneAlertsEnabled(v);
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSwitchRow(
                        icon: Icons.alarm_rounded,
                        iconColor: cfo.transfer,
                        iconBackground: cfo.transferContainer,
                        title: 'Daily Check-In',
                        subtitle:
                            'Reminder at ${TimeOfDay(hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute).format(context)}',
                        value: settings.dailyReminderEnabled,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          context.read<SettingsCubit>().setDailyReminder(
                            enabled: v,
                          );
                        },
                      ),
                      if (profile != null) ...[
                        Divider(height: 1, color: cfo.divider),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  key: const Key(
                                    'settings_send_test_notification_btn',
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 40),
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await GetIt.I<FinancialAlertsCoordinator>()
                                        .sendTestNotification(profile.id);
                                  },
                                  icon: const Icon(
                                    Icons.notifications_active_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Send Test Alert'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                onPressed: () => context.push('/notifications'),
                                child: const Text('Inbox'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Vault Security
              const SectionHeader(title: 'Vault Security'),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 2,
                child: PressScaleCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      FintechSwitchRow(
                        icon: Icons.fingerprint_rounded,
                        iconColor: scheme.primary,
                        iconBackground: scheme.primaryContainer,
                        title: 'Biometric & PIN Lock',
                        subtitle: lock.isEnabled
                            ? '${lock.biometricEnabled ? "Biometric + PIN" : "PIN Only"} • ${lock.timeoutSeconds}s'
                            : 'Off • Tap to protect local vault',
                        value: lock.isEnabled,
                        onChanged: (enable) {
                          HapticFeedback.selectionClick();
                          if (enable) {
                            _openConfigureLockDialog(context, lock);
                          } else {
                            _openVerifyDisableLockDialog(context);
                          }
                        },
                      ),
                      if (lock.isEnabled) ...[
                        Divider(height: 1, color: cfo.divider),
                        FintechSettingRow(
                          icon: Icons.password_rounded,
                          iconColor: scheme.primary,
                          iconBackground: scheme.primaryContainer,
                          title: 'Change App PIN',
                          subtitle: 'Update your fallback vault passcode',
                          onTap: () => _openChangePinDialog(context),
                        ),
                        Divider(height: 1, color: cfo.divider),
                        FintechSettingRow(
                          icon: Icons.lock_clock_outlined,
                          iconColor: cfo.warning,
                          iconBackground: cfo.warningContainer,
                          title: 'Lock App Now',
                          subtitle: 'Require PIN or biometric immediately',
                          onTap: () => context.read<AppLockCubit>().lockNow(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 4. Device & Session (FR-021)
              const SectionHeader(title: 'Device & Session (FR-021)'),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 3,
                child: _DeviceSessionCard(
                  auth: auth,
                  env: env,
                  onConfirmLogout: (isLocal) =>
                      _confirmSignOut(context, isLocal: isLocal),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 5. Ledger Integrity & Diagnostics
              const SectionHeader(title: 'Ledger Integrity & Diagnostics'),
              const SizedBox(height: AppSpacing.xs),
              StaggeredFadeSlide(
                index: 4,
                child: PressScaleCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      FintechSettingRow(
                        icon: Icons.verified_outlined,
                        iconColor: cfo.success,
                        iconBackground: cfo.successContainer,
                        title: 'Ledger Reconciliation',
                        subtitle: 'Verify all journals balance to exact unit',
                        onTap: profile == null
                            ? null
                            : () async {
                                final rep =
                                    await GetIt.I<TransactionRepository>()
                                        .runReconciliationCheck(profile.id);
                                if (!context.mounted) return;
                                final r = rep.valueOrNull;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                      r != null && r.isHealthy
                                          ? 'Healthy: ${r.postedJournalCount} posted journals reconciled (Debits == Credits).'
                                          : 'Reconciliation warning: check diagnostics.',
                                    ),
                                  ),
                                );
                              },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSettingRow(
                        icon: Icons.bug_report_outlined,
                        iconColor: cfo.transfer,
                        iconBackground: cfo.transferContainer,
                        title: 'Copy Support Diagnostics',
                        subtitle: 'Redacted logs without amounts or keys',
                        onTap: () async {
                          final supportId = GetIt.I<IdGenerator>().nextUuid();
                          final bundle = GetIt.I<RedactingLogger>()
                              .exportSupportDiagnostics(
                                appVersion: env.appVersion,
                                platform: 'flutter',
                                supportCorrelationId: supportId,
                              );
                          await Clipboard.setData(ClipboardData(text: bundle));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  'Redacted diagnostics copied (Support ID: ${supportId.substring(0, 8)}).',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSettingRow(
                        icon: Icons.backup_outlined,
                        iconColor: scheme.primary,
                        iconBackground: scheme.primaryContainer,
                        title: 'Encrypted Backup (.pcfo)',
                        subtitle: 'Export or restore local vault archive',
                        onTap: () => context.push('/backup'),
                      ),
                      Divider(height: 1, color: cfo.divider),
                      FintechSettingRow(
                        key: const Key('settings_replay_onboarding_tile'),
                        icon: Icons.auto_awesome_rounded,
                        iconColor: scheme.primary,
                        iconBackground: scheme.primaryContainer,
                        title: 'App Walkthrough Tour',
                        subtitle: 'Revisit vaults, ledger, budgets & privacy',
                        onTap: () => context.push('/onboarding?replay=true'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openConfigureLockDialog(
    BuildContext context,
    AppLockState lockState,
  ) async {
    await showModernDialog<void>(
      context: context,
      builder: (_) => _ConfigureLockDialog(lockState: lockState),
    );
  }

  Future<void> _handleBlockScreenshotsToggle(
    BuildContext context,
    bool enable,
    AppLockState lockState,
  ) async {
    HapticFeedback.selectionClick();
    final settingsCubit = context.read<SettingsCubit>();
    if (enable) {
      await settingsCubit.setBlockScreenshots(true);
      if (context.mounted) {
        showFintechToast(
          context,
          'Screenshots & screen recording are now blocked.',
          tone: FintechToastTone.success,
        );
      }
      return;
    }

    if (lockState.isEnabled) {
      await showModernDialog<void>(
        context: context,
        builder: (_) => _VerifyPinActionDialog(
          title: 'Verify PIN to Allow Screenshots',
          subtitle:
              'Confirm your vault PIN before disabling screenshot & recording protection',
          icon: Icons.screenshot_outlined,
          confirmLabel: 'Allow Screenshots',
          incorrectPinMessage: 'Incorrect PIN. Protection remains active.',
          onVerified: () async {
            await settingsCubit.setBlockScreenshots(false);
            if (context.mounted) {
              showFintechToast(
                context,
                'Screenshots & recording allowed. Tap the eye icon anytime to mask amounts.',
                tone: FintechToastTone.warning,
              );
            }
          },
        ),
      );
      return;
    }

    final confirmed = await showModernConfirmDialog(
      context: context,
      title: 'Allow Screenshots & Recording?',
      subtitle: 'Temporarily lift OS screen-capture block',
      icon: Icons.screenshot_outlined,
      accent: ModernDialogAccent.warning,
      confirmLabel: 'Allow Screenshots',
      message:
          'Screenshots, screen recording, and screen casting will be allowed until you turn protection back on. Tip: tap the eye icon in the top bar anytime to mask balances.',
    );
    if (confirmed == true && context.mounted) {
      await settingsCubit.setBlockScreenshots(false);
      if (context.mounted) {
        showFintechToast(
          context,
          'Screenshots & screen recording are now allowed.',
          tone: FintechToastTone.info,
        );
      }
    }
  }

  Future<void> _openVerifyDisableLockDialog(BuildContext context) async {
    await showModernDialog<void>(
      context: context,
      builder: (_) => _VerifyPinActionDialog(
        title: 'Verify PIN to Disable Lock',
        subtitle: 'Confirm your current PIN before removing vault protection',
        icon: Icons.lock_open_rounded,
        confirmLabel: 'Disable Lock',
        incorrectPinMessage: 'Incorrect PIN. Lock remains active.',
        onVerified: () async {
          await context.read<AppLockCubit>().disableLock();
          if (context.mounted) {
            showFintechToast(
              context,
              'App Lock disabled.',
              tone: FintechToastTone.info,
            );
          }
        },
      ),
    );
  }

  Future<void> _openChangePinDialog(BuildContext context) async {
    await showModernDialog<void>(
      context: context,
      builder: (_) => const _ChangePinDialog(),
    );
  }

  Future<void> _openCustomLowBalanceDialog(
    BuildContext context,
    String ccy,
    int minorFactor,
    int currentMinor,
  ) async {
    await showModernDialog<void>(
      context: context,
      builder: (_) => _CustomLowBalanceDialog(
        currencyCode: ccy,
        minorFactor: minorFactor,
        currentMinor: currentMinor,
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context, {
    required bool isLocal,
  }) async {
    final confirmed = await showModernConfirmDialog(
      context: context,
      title: isLocal ? 'Switch Account?' : 'Sign Out?',
      subtitle: 'Encrypted local vaults remain safely on device',
      icon: Icons.logout_rounded,
      accent: ModernDialogAccent.danger,
      confirmLabel: isLocal ? 'Switch Account' : 'Sign Out',
      message: isLocal
          ? 'Your local encrypted profiles and transactions stay safe on this device. You can return anytime or sign in to a cloud account.'
          : 'You will be signed out of this cloud session. Local encrypted data stays protected.',
    );
    if (confirmed == true && context.mounted) {
      context.read<ActiveProfileCubit>().clearOnLogout();
      await context.read<AuthCubit>().logout();
    }
  }
}

class _DeviceSessionCard extends StatefulWidget {
  const _DeviceSessionCard({
    required this.auth,
    required this.env,
    required this.onConfirmLogout,
  });

  final AuthState auth;
  final EnvironmentConfig env;
  final ValueChanged<bool> onConfirmLogout;

  @override
  State<_DeviceSessionCard> createState() => _DeviceSessionCardState();
}

class _DeviceSessionCardState extends State<_DeviceSessionCard> {
  late final Future<String> _deviceIdFuture;

  @override
  void initState() {
    super.initState();
    _deviceIdFuture = GetIt.I<KeyManager>().getOrCreateDeviceId();
  }

  static String _shortDeviceId(String raw) {
    if (raw.length <= 16) return raw;
    return '${raw.substring(0, 8)}…${raw.substring(raw.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isLocal = widget.auth.user?.isLocalOnlyWorkspace ?? true;

    return FutureBuilder<String>(
      future: _deviceIdFuture,
      builder: (context, devSnap) {
        final devId = devSnap.data ?? 'Initializing...';
        return PressScaleCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              FintechSettingRow(
                icon: Icons.devices_rounded,
                iconColor: cfo.transfer,
                iconBackground: cfo.transferContainer,
                title: isLocal
                    ? 'Offline Local Vault'
                    : 'Cloud Synced (${widget.auth.user?.email ?? ""})',
                subtitle: 'Device • ${_shortDeviceId(devId)}',
                showChevron: false,
                trailing: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: cfo.subtleText,
                ),
                onTap: devSnap.hasData
                    ? () async {
                        HapticFeedback.selectionClick();
                        await Clipboard.setData(ClipboardData(text: devId));
                        if (context.mounted) {
                          showFintechToast(
                            context,
                            'Device ID copied.',
                            tone: FintechToastTone.success,
                          );
                        }
                      }
                    : null,
              ),
              Divider(height: 1, color: cfo.divider),
              FintechSettingRow(
                icon: Icons.logout_rounded,
                iconColor: cfo.expense,
                iconBackground: cfo.expenseContainer,
                title: isLocal ? 'Switch to Cloud Account' : 'Sign Out',
                subtitle:
                    '${widget.env.environment.name.toUpperCase()} • v${widget.env.appVersion}',
                onTap: () => widget.onConfirmLogout(isLocal),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConfigureLockDialog extends StatefulWidget {
  const _ConfigureLockDialog({required this.lockState});
  final AppLockState lockState;

  @override
  State<_ConfigureLockDialog> createState() => _ConfigureLockDialogState();
}

class _ConfigureLockDialogState extends State<_ConfigureLockDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  late bool _useBio;
  var _timeoutSec = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useBio = widget.lockState.biometricAvailable;
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return ModernDialogShell(
      title: 'Configure App Lock',
      subtitle: 'Protect your local encrypted vaults with PIN & biometrics',
      icon: Icons.fingerprint_rounded,
      confirmLabel: 'Enable Lock',
      onConfirm: () async {
        final pin = _pinCtrl.text.trim();
        final confirmPin = _confirmPinCtrl.text.trim();
        if (pin.length < 4 || pin.length > 12) {
          setState(() => _error = 'Enter a PIN between 4 and 12 digits.');
          return;
        }
        if (pin != confirmPin) {
          setState(() => _error = 'PINs do not match.');
          return;
        }
        HapticFeedback.selectionClick();
        await context.read<AppLockCubit>().configureLock(
          fallbackPin: pin,
          useBiometrics: _useBio,
          timeoutSeconds: _timeoutSec,
        );
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: Text(
              'A fallback PIN (4–12 digits) is required in case biometrics fail or are unavailable.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cfo.subtleText,
                height: 1.35,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.expense,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FintechTextField(
            label: 'Fallback App PIN (4–12 digits)',
            controller: _pinCtrl,
            leadingIcon: Icons.pin_outlined,
            obscureText: true,
            enableObscureToggle: true,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 10),
          FintechTextField(
            label: 'Confirm App PIN',
            controller: _confirmPinCtrl,
            leadingIcon: Icons.verified_user_outlined,
            obscureText: true,
            enableObscureToggle: true,
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 10),
          FintechSwitchCard(
            title: 'Enable Biometrics',
            subtitle: widget.lockState.biometricAvailable
                ? 'Use Face ID or Fingerprint to unlock'
                : 'Biometric hardware unavailable on device',
            value: _useBio,
            onChanged: widget.lockState.biometricAvailable
                ? (v) => setState(() => _useBio = v)
                : null,
          ),
          const SizedBox(height: 12),
          FintechDropdownField<int>(
            key: const Key('app_lock_timeout_dropdown'),
            label: 'Auto-lock timeout',
            value: _timeoutSec,
            leadingIcon: Icons.timer_outlined,
            options: const [
              FintechDropdownOption<int>(
                value: 0,
                label: 'Immediately',
                subtitle: 'Lock whenever the app goes to background',
                icon: Icons.bolt_rounded,
              ),
              FintechDropdownOption<int>(
                value: 30,
                label: '30 seconds',
                subtitle: 'Balanced protection for quick app switching',
                icon: Icons.timer_outlined,
              ),
              FintechDropdownOption<int>(
                value: 60,
                label: '1 minute',
                subtitle: 'Lock after 1 minute away',
                icon: Icons.schedule_rounded,
              ),
              FintechDropdownOption<int>(
                value: 300,
                label: '5 minutes',
                subtitle: 'Relaxed timeout for multi-app workflows',
                icon: Icons.hourglass_bottom_rounded,
              ),
            ],
            onChanged: (v) => setState(() => _timeoutSec = v),
          ),
        ],
      ),
    );
  }
}

class _VerifyPinActionDialog extends StatefulWidget {
  const _VerifyPinActionDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.confirmLabel,
    required this.incorrectPinMessage,
    required this.onVerified,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String confirmLabel;
  final String incorrectPinMessage;
  final Future<void> Function() onVerified;

  @override
  State<_VerifyPinActionDialog> createState() => _VerifyPinActionDialogState();
}

class _VerifyPinActionDialogState extends State<_VerifyPinActionDialog> {
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _verifying = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return ModernDialogShell(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      accent: ModernDialogAccent.warning,
      confirmLabel: widget.confirmLabel,
      isConfirmLoading: _verifying,
      onConfirm: () async {
        final pin = _pinCtrl.text.trim();
        if (pin.isEmpty) {
          setState(() => _error = 'Enter your current PIN.');
          return;
        }
        setState(() {
          _verifying = true;
          _error = null;
        });
        final cubit = context.read<AppLockCubit>();
        final ok = await cubit.verifyCurrentPin(pin);
        if (!context.mounted) return;
        if (!ok) {
          HapticFeedback.heavyImpact();
          setState(() {
            _verifying = false;
            _error = widget.incorrectPinMessage;
          });
          return;
        }
        await widget.onVerified();
        if (context.mounted) {
          Navigator.of(context).pop();
        }
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
            label: 'Current App PIN',
            controller: _pinCtrl,
            leadingIcon: Icons.pin_outlined,
            obscureText: true,
            enableObscureToggle: true,
            autofocus: true,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return ModernDialogShell(
      title: 'Change App PIN',
      subtitle: 'Verify your current PIN and choose a new 4–12 digit code',
      icon: Icons.password_rounded,
      confirmLabel: 'Update PIN',
      isConfirmLoading: _saving,
      onConfirm: () async {
        final cur = _currentCtrl.text.trim();
        final next = _newCtrl.text.trim();
        final conf = _confirmCtrl.text.trim();
        if (cur.isEmpty) {
          setState(() => _error = 'Enter your current PIN.');
          return;
        }
        if (next.length < 4 || next.length > 12) {
          setState(() => _error = 'New PIN must be 4–12 digits.');
          return;
        }
        if (next != conf) {
          setState(() => _error = 'New PINs do not match.');
          return;
        }
        setState(() {
          _saving = true;
          _error = null;
        });
        final ok = await context.read<AppLockCubit>().changePin(
          currentPin: cur,
          newPin: next,
        );
        if (!context.mounted) return;
        if (!ok) {
          HapticFeedback.heavyImpact();
          setState(() {
            _saving = false;
            _error = 'Current PIN is incorrect.';
          });
          return;
        }
        Navigator.of(context).pop();
        showFintechToast(
          context,
          'App PIN updated.',
          tone: FintechToastTone.success,
        );
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
            label: 'Current PIN',
            controller: _currentCtrl,
            leadingIcon: Icons.lock_outline_rounded,
            obscureText: true,
            enableObscureToggle: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          FintechTextField(
            label: 'New PIN (4–12 digits)',
            controller: _newCtrl,
            leadingIcon: Icons.pin_outlined,
            obscureText: true,
            enableObscureToggle: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          FintechTextField(
            label: 'Confirm New PIN',
            controller: _confirmCtrl,
            leadingIcon: Icons.verified_user_outlined,
            obscureText: true,
            enableObscureToggle: true,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }
}

class _CustomLowBalanceDialog extends StatefulWidget {
  const _CustomLowBalanceDialog({
    required this.currencyCode,
    required this.minorFactor,
    required this.currentMinor,
  });

  final String currencyCode;
  final int minorFactor;
  final int currentMinor;

  @override
  State<_CustomLowBalanceDialog> createState() =>
      _CustomLowBalanceDialogState();
}

class _CustomLowBalanceDialogState extends State<_CustomLowBalanceDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: (widget.currentMinor / widget.minorFactor).round().toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return ModernDialogShell(
      title: 'Custom Low Balance Limit',
      subtitle: 'Warn when any Bank, Cash or Wallet drops below this amount',
      icon: Icons.account_balance_wallet_outlined,
      confirmLabel: 'Save Limit',
      onConfirm: () {
        final parsed = double.tryParse(_ctrl.text.trim().replaceAll(',', ''));
        if (parsed == null || parsed <= 0) {
          setState(() => _error = 'Enter a valid positive amount.');
          return;
        }
        final minor = (parsed * widget.minorFactor).round();
        HapticFeedback.selectionClick();
        context.read<SettingsCubit>().setLowBalanceThresholdMinor(minor);
        Navigator.of(context).pop();
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
            label: 'Threshold (${widget.currencyCode})',
            controller: _ctrl,
            leadingIcon: Icons.payments_outlined,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
    );
  }
}
