import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/config/environment_config.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/editorial_bento_kit.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../authentication/presentation/bloc/auth_cubit.dart';
import '../../../budgets/presentation/pages/budgets_page.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../notifications/presentation/bloc/notifications_cubit.dart';
import '../../../security_lock/presentation/bloc/app_lock_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../bloc/active_profile_cubit.dart';
import 'profiles_page.dart';

/// Bottom-navigation **Profile & Vault Command Hub** screen:
/// Elevated profile identity hero with Play Store swipe-down switch and
/// horizontal overlapping Family Members avatar stack, live Vault Security &
/// Readiness gauge + 1-tap Double-Entry Ledger Audit, interactive financial
/// snapshot, zero-horizontal-scroll Vault Roster switcher, live-badged Finance
/// Sections, compact Workspace & Security links, and Account Session controls.
class ProfileHubPage extends StatefulWidget {
  const ProfileHubPage({super.key});

  @override
  State<ProfileHubPage> createState() => _ProfileHubPageState();
}

class _ProfileHubPageState extends State<ProfileHubPage> {
  bool _auditing = false;
  String? _auditProfileId;
  bool? _auditHealthy;
  int? _auditJournalCount;

  String? _membersProfileId;
  List<ProfileMember> _members = const [];

  Future<void> _loadMembers(FinancialProfile profile, String userId) async {
    _membersProfileId = profile.id.value;
    final res = await GetIt.I<ProfileRepository>().listMembers(
      profileId: profile.id,
      requestingUserId: userId,
    );
    if (!mounted || _membersProfileId != profile.id.value) return;
    setState(() {
      _members = (res.valueOrNull ?? const <ProfileMember>[])
          .where((m) => m.status == 'active')
          .toList();
    });
  }

  Future<void> _runLedgerAudit(FinancialProfile profile) async {
    if (_auditing) return;
    HapticFeedback.selectionClick();
    setState(() => _auditing = true);
    try {
      final res = await GetIt.I<TransactionRepository>().runReconciliationCheck(
        profile.id,
      );
      if (!mounted) return;
      final report = res.valueOrNull;
      setState(() {
        _auditProfileId = profile.id.value;
        _auditHealthy = report?.isHealthy ?? false;
        _auditJournalCount = report?.postedJournalCount ?? 0;
      });
      if (report != null && report.isHealthy) {
        context.read<NotificationsCubit>().triggerCelebration();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            report != null && report.isHealthy
                ? 'Ledger verified: ${report.postedJournalCount} posted journal(s) balanced (Debits == Credits).'
                : 'Ledger check found a discrepancy — inspect Settings diagnostics.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _auditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ActiveProfileCubit>().state;
    final activeProfile = profileState.activeProfile;
    final profiles = profileState.profiles;
    final settings = context.watch<SettingsCubit>().state;
    final auth = context.watch<AuthCubit>().state;
    final lock = context.watch<AppLockCubit>().state;
    final dashState = context.watch<DashboardBloc>().state;
    final env = GetIt.I<EnvironmentConfig>();
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    if (activeProfile == null) {
      return EmptyStateView(
        icon: Icons.person_outline_rounded,
        title: 'No active profile selected',
        description:
            'Create or select a financial profile to inspect vault metrics, preferences, and tools.',
        actionLabel: 'Create Profile',
        onAction: () => openCreateProfileModal(context),
      );
    }

    final summary = dashState.summary;
    final budgets = dashState.budgets;
    final accountsCount = summary?.accounts.length ?? 0;
    final pendingSyncCount = summary?.pendingSyncCount ?? 0;
    final ccy = activeProfile.baseCurrencyCode;
    final netWorth = summary?.netWorth ?? Money.zero(ccy);
    final totalAssets = summary?.totalAssets ?? Money.zero(ccy);
    final periodIncome = summary?.periodIncome ?? Money.zero(ccy);
    final periodSpend = summary?.periodNetExpense ?? Money.zero(ccy);
    final isLocalSession = auth.user?.isLocalOnlyWorkspace ?? true;
    final currentUserId = auth.user?.id ?? 'local-owner';

    if (_membersProfileId != activeProfile.id.value) {
      _membersProfileId = activeProfile.id.value;
      Future.microtask(() => _loadMembers(activeProfile, currentUserId));
    }
    final activeMembers = _membersProfileId == activeProfile.id.value
        ? _members
        : const <ProfileMember>[];

    final auditMatchesProfile = _auditProfileId == activeProfile.id.value;
    final privacyStrong =
        settings.privacyCurtainEnabled && settings.blockScreenshotsEnabled;
    final readinessScore =
        25 + // AES-256 SQLite encryption always active
        (accountsCount > 0 ? 20 : 0) +
        (budgets.isNotEmpty ? 20 : 0) +
        (lock.isEnabled ? 20 : 0) +
        (privacyStrong ? 15 : 0);
    final activeThemeLabel = switch (settings.themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Auto',
    };

    return SingleChildScrollView(
      padding: EnterprisePageContainer.responsivePadding(context, bottom: 44),
      child: EnterprisePageContainer(
        maxWidth: AppBreakpoints.maxContentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Signature Gradient Profile Identity Banner with Family Members Stack
            StaggeredFadeSlide(
              index: 0,
              child: _ProfileIdentityHeroCard(
                activeProfile: activeProfile,
                profilesCount: profiles.length,
                accountsCount: accountsCount,
                budgetsCount: budgets.length,
                members: activeMembers,
                onEdit: () => openEditProfileModal(context, activeProfile),
                onOpenMembers: () => openProfileMembersModal(
                  context,
                  activeProfile,
                  onUpdated: () => _loadMembers(activeProfile, currentUserId),
                ),
                onAddMember: () => openAddFamilyMemberDialog(
                  context,
                  activeProfile,
                  onSaved: () => _loadMembers(activeProfile, currentUserId),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Live Vault Security & Readiness Studio + 1-Tap Ledger Audit
            StaggeredFadeSlide(
              index: 1,
              child: _VaultReadinessCard(
                profile: activeProfile,
                readinessScore: readinessScore,
                hasAccounts: accountsCount > 0,
                hasBudgets: budgets.isNotEmpty,
                lockEnabled: lock.isEnabled,
                privacyEnabled: privacyStrong,
                auditing: _auditing,
                auditHealthy: auditMatchesProfile ? _auditHealthy : null,
                auditJournalCount: auditMatchesProfile
                    ? _auditJournalCount
                    : null,
                onRunAudit: () => _runLedgerAudit(activeProfile),
                onEnableLock: () => context.push('/settings'),
                onSetBudget: () => openCreateBudgetModal(
                  context,
                  activeProfile,
                  suggestedName: 'Monthly Spending',
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 3. Interactive Live Financial Snapshot
            StaggeredFadeSlide(
              index: 2,
              child: Builder(
                builder: (context) {
                  final metrics = [
                    (
                      label: 'Net Worth',
                      money: netWorth,
                      kind: 'neutral',
                      icon: Icons.account_balance_rounded,
                      fg: scheme.primary,
                      bg: scheme.primaryContainer,
                      route: '/accounts',
                    ),
                    (
                      label: 'Total Assets',
                      money: totalAssets,
                      kind: 'income',
                      icon: Icons.savings_outlined,
                      fg: cfo.income,
                      bg: cfo.incomeContainer,
                      route: '/accounts',
                    ),
                    (
                      label: 'Period Income',
                      money: periodIncome,
                      kind: 'income',
                      icon: Icons.south_west_rounded,
                      fg: cfo.income,
                      bg: cfo.incomeContainer,
                      route: '/transactions',
                    ),
                    (
                      label: 'Period Spend',
                      money: periodSpend,
                      kind: 'expense',
                      icon: Icons.north_east_rounded,
                      fg: cfo.expense,
                      bg: cfo.expenseContainer,
                      route: '/transactions',
                    ),
                  ];

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cfo.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cfo.divider),
                    ),
                    child: Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: _CompactVaultMetricCell(
                                  label: metrics[0].label,
                                  money: metrics[0].money,
                                  masked: settings.hideBalances,
                                  icon: metrics[0].icon,
                                  color: metrics[0].fg,
                                  onTap: () => context.go(metrics[0].route),
                                ),
                              ),
                              VerticalDivider(
                                width: 20,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _CompactVaultMetricCell(
                                  label: metrics[1].label,
                                  money: metrics[1].money,
                                  masked: settings.hideBalances,
                                  icon: metrics[1].icon,
                                  color: metrics[1].fg,
                                  onTap: () => context.go(metrics[1].route),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 18, color: cfo.divider),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: _CompactVaultMetricCell(
                                  label: metrics[2].label,
                                  money: metrics[2].money,
                                  masked: settings.hideBalances,
                                  icon: metrics[2].icon,
                                  color: metrics[2].fg,
                                  onTap: () => context.go(metrics[2].route),
                                ),
                              ),
                              VerticalDivider(
                                width: 20,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _CompactVaultMetricCell(
                                  label: metrics[3].label,
                                  money: metrics[3].money,
                                  masked: settings.hideBalances,
                                  icon: metrics[3].icon,
                                  color: metrics[3].fg,
                                  onTap: () => context.go(metrics[3].route),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 4. Zero-Horizontal-Scroll Vault Switcher Roster
            SectionHeader(
              title: 'Financial Profiles (${profiles.length})',
              subtitle: 'Tap any vault to switch instantly',
              trailingLabel: 'Manage All',
              onTrailingPressed: () => context.push('/profiles'),
            ),
            const SizedBox(height: AppSpacing.xs),
            StaggeredFadeSlide(
              index: 3,
              child: PressScaleCard(
                key: const Key('profile_vault_roster'),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < profiles.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: cfo.divider),
                      _VaultRosterRow(
                        profile: profiles[i],
                        isSelected: profiles[i].id == activeProfile.id,
                        onEdit:
                            profiles[i].permissions.canChangeSettingsOrCurrency
                            ? () => openEditProfileModal(context, profiles[i])
                            : null,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.read<ActiveProfileCubit>().switchProfile(
                            profiles[i].id,
                          );
                        },
                      ),
                    ],
                    Divider(height: 1, color: cfo.divider),
                    InkWell(
                      onTap: () => openCreateProfileModal(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 17,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Add Profile',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 5. All Finance Sections & Tools with Live Counter Badges
            const SectionHeader(
              title: 'Finance Sections & Tools',
              subtitle: 'Complete toolkit for this profile',
            ),
            const SizedBox(height: AppSpacing.xs),
            StaggeredFadeSlide(
              index: 4,
              child: PressScaleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    FintechSettingRow(
                      key: const Key('profile_open_coach_tile'),
                      icon: Icons.auto_awesome_rounded,
                      iconColor: scheme.primary,
                      iconBackground: scheme.primaryContainer,
                      title: 'Smart CFO Coach',
                      subtitle: 'Monthly spend audit, smart budgets & AI Q&A',
                      trailing: FintechStatusPill(
                        label: 'FREE AI',
                        foreground: cfo.income,
                        background: cfo.incomeContainer,
                      ),
                      onTap: () => context.push('/coach'),
                    ),
                    Divider(height: 1, color: cfo.divider),
                    FintechSettingRow(
                      key: const Key('profile_open_life_planner_tile'),
                      icon: Icons.family_restroom_rounded,
                      iconColor: cfo.income,
                      iconBackground: cfo.incomeContainer,
                      title: 'Life & EMI Planner',
                      subtitle: 'Bachelor, Family & EMI payoff simulator',
                      trailing: FintechStatusPill(
                        label: 'STATUS',
                        foreground: scheme.primary,
                        background: scheme.primaryContainer,
                      ),
                      onTap: () => context.push('/life-planner'),
                    ),
                    Divider(height: 1, color: cfo.divider),
                    FintechSettingRow(
                      key: const Key('profile_open_monthly_tile'),
                      icon: Icons.calendar_month_rounded,
                      iconColor: scheme.primary,
                      iconBackground: scheme.primaryContainer,
                      title: 'Monthly Tracker & Bucket List',
                      subtitle:
                          'Net savings, purchase planner & extra income split',
                      trailing: FintechStatusPill(
                        label: 'NEW',
                        foreground: cfo.income,
                        background: cfo.incomeContainer,
                      ),
                      onTap: () => context.push('/monthly'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            StaggeredFadeSlide(
              index: 5,
              child: _FinanceSectionsGrid(
                cfo: cfo,
                scheme: scheme,
                budgetsCount: budgets.length,
                pendingSyncCount: pendingSyncCount,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 6. Workspace & Security (compact, aligned, single-line rows)
            const SectionHeader(title: 'Workspace & Security'),
            const SizedBox(height: AppSpacing.xs),
            PressScaleCard(
              key: const Key('profile_workspace_security_card'),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  FintechSettingRow(
                    icon: Icons.fingerprint_rounded,
                    iconColor: scheme.primary,
                    iconBackground: scheme.primaryContainer,
                    title: 'App Lock',
                    subtitle: lock.isEnabled
                        ? '${lock.timeoutSeconds}s auto-lock active'
                        : 'Protect vault with PIN or biometrics',
                    trailing: FintechStatusPill(
                      label: lock.isEnabled ? 'ON' : 'OFF',
                      foreground: lock.isEnabled ? cfo.income : cfo.subtleText,
                      background: lock.isEnabled
                          ? cfo.incomeContainer
                          : cfo.surfaceTonal,
                    ),
                    onTap: () => context.push('/settings'),
                  ),
                  Divider(height: 1, color: cfo.divider),
                  FintechSettingRow(
                    icon: Icons.notifications_none_rounded,
                    iconColor: cfo.warning,
                    iconBackground: cfo.warningContainer,
                    title: 'Notifications & Alerts',
                    subtitle: 'Bills, budget limits & alerts',
                    onTap: () => context.push('/notifications'),
                  ),
                  Divider(height: 1, color: cfo.divider),
                  FintechSettingRow(
                    key: const Key('profile_open_settings_tile'),
                    icon: Icons.tune_rounded,
                    iconColor: cfo.transfer,
                    iconBackground: cfo.transferContainer,
                    title: 'Settings & Security',
                    subtitle:
                        'Theme ($activeThemeLabel), privacy & diagnostics',
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // 7. Account Session & Logout
            const SectionHeader(title: 'Account & Session'),
            const SizedBox(height: AppSpacing.xs),
            PressScaleCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconSquircle(
                        icon: isLocalSession
                            ? Icons.shield_outlined
                            : Icons.cloud_done_outlined,
                        iconColor: cfo.success,
                        backgroundColor: cfo.successContainer,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLocalSession
                                  ? 'Offline Encrypted Workspace'
                                  : (auth.user?.displayName ?? 'Cloud Account'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              isLocalSession
                                  ? 'AES-256 SQLite vault • v${env.appVersion}'
                                  : '${auth.user?.email ?? ""} • v${env.appVersion}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cfo.subtleText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('profile_logout_button'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      foregroundColor: cfo.expense,
                      side: BorderSide(
                        color: cfo.expense.withValues(alpha: 0.45),
                      ),
                    ),
                    onPressed: () =>
                        _confirmLogout(context, isLocalSession: isLocalSession),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: Text(
                      isLocalSession ? 'Log Out / Switch Account' : 'Log Out',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(
    BuildContext context, {
    required bool isLocalSession,
  }) async {
    final confirmed = await showModernConfirmDialog(
      context: context,
      title: 'Log Out of Workspace?',
      subtitle: 'Encrypted local vaults stay safe on device',
      icon: Icons.logout_rounded,
      accent: ModernDialogAccent.danger,
      confirmLabel: 'Log Out',
      confirmKey: const Key('confirm_logout_action'),
      message: isLocalSession
          ? 'Your local encrypted profiles and transactions remain safely stored on this device. You can return anytime or sign in to a cloud account.'
          : 'You will be signed out of this session. Local encrypted data remains protected.',
    );
    if (confirmed == true && context.mounted) {
      context.read<ActiveProfileCubit>().clearOnLogout();
      await context.read<AuthCubit>().logout();
    }
  }
}

class _ProfileIdentityHeroCard extends StatefulWidget {
  const _ProfileIdentityHeroCard({
    required this.activeProfile,
    required this.profilesCount,
    required this.accountsCount,
    required this.budgetsCount,
    required this.members,
    required this.onEdit,
    required this.onOpenMembers,
    required this.onAddMember,
  });

  final FinancialProfile activeProfile;
  final int profilesCount;
  final int accountsCount;
  final int budgetsCount;
  final List<ProfileMember> members;
  final VoidCallback onEdit;
  final VoidCallback onOpenMembers;
  final VoidCallback onAddMember;

  @override
  State<_ProfileIdentityHeroCard> createState() =>
      _ProfileIdentityHeroCardState();
}

class _ProfileIdentityHeroCardState extends State<_ProfileIdentityHeroCard> {
  double _dragDy = 0;

  @override
  Widget build(BuildContext context) {
    final profile = widget.activeProfile;
    final effectiveMembers = widget.members.isNotEmpty
        ? widget.members
        : <ProfileMember>[
            ProfileMember(
              id: 'owner-${profile.id.value}',
              profileId: profile.id,
              userId: 'local-owner',
              displayName: profile.name,
              role: profile.role,
              status: 'active',
              createdAtUtc: profile.createdAtUtc,
            ),
          ];

    return FintechSignatureHero(
      tone: SignatureHeroTone.violet,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      bottomBar: _FamilyMembersHeroDock(
        members: effectiveMembers,
        canManageMembers: profile.permissions.canManageMembers,
        onTapMembers: widget.onOpenMembers,
        onAddMember: widget.onAddMember,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                _dragDy = (_dragDy + d.delta.dy * 0.5).clamp(-18.0, 22.0);
              });
            },
            onVerticalDragEnd: (d) async {
              final raw = _dragDy;
              final vy = d.primaryVelocity ?? 0;
              setState(() => _dragDy = 0);
              if (raw.abs() >= 14 || vy.abs() >= 200) {
                if (widget.profilesCount > 1) {
                  HapticFeedback.mediumImpact();
                  final isDown = raw >= 0 && vy >= -180;
                  await context.read<ActiveProfileCubit>().cycleNextProfile(
                    reverse: !isDown,
                  );
                }
              }
            },
            onVerticalDragCancel: () => setState(() => _dragDy = 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              transform: Matrix4.translationValues(0, _dragDy, 0),
              child: ProfileAvatar(
                profile: profile,
                size: 56,
                selectedRing: true,
                showTypeBadge: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRIVATE WEALTH VAULT',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: const Color(0xFFF0CF7E),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9.5,
                                  letterSpacing: 1.35,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 21,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (profile.permissions.canChangeSettingsOrCurrency) ...[
                      const SizedBox(width: 6),
                      Material(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: CircleBorder(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                        ),
                        child: InkWell(
                          key: const Key('profile_hub_edit_btn'),
                          customBorder: const CircleBorder(),
                          onTap: widget.onEdit,
                          child: const Tooltip(
                            message: 'Edit profile',
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    HeroGlassPill(
                      label: profile.profileType.label,
                      foreground: const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${profile.baseCurrencyCode} • ${profile.role.label} • ${widget.accountsCount == 1 ? '1 acct' : '${widget.accountsCount} accts'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactVaultMetricCell extends StatelessWidget {
  const _CompactVaultMetricCell({
    required this.label,
    required this.money,
    required this.masked,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Money money;
  final bool masked;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: cfo.subtleText,
                ),
              ],
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedMoneyText(
                money: money,
                masked: masked,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyMembersHeroDock extends StatelessWidget {
  const _FamilyMembersHeroDock({
    required this.members,
    required this.canManageMembers,
    required this.onTapMembers,
    required this.onAddMember,
  });

  final List<ProfileMember> members;
  final bool canManageMembers;
  final VoidCallback onTapMembers;
  final VoidCallback onAddMember;

  String _memberSummaryText() {
    if (members.isEmpty) return 'Invite family';
    if (members.length == 1) return members.first.displayName;
    if (members.length == 2) {
      return '${members[0].displayName}, ${members[1].displayName}';
    }
    return '${members[0].displayName}, ${members[1].displayName} +${members.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    const heroBgRing = Color(0xFF102654);

    return InkWell(
      key: const Key('profile_family_members_strip'),
      onTap: onTapMembers,
      splashColor: Colors.white.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, 12, 11),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxVisible = constraints.maxWidth < 310 ? 4 : 5;
            final visible = members.take(maxVisible).toList();
            final overflowCount = members.length - visible.length;
            final showInviteCircle = members.length <= 1 && canManageMembers;
            final totalCircles =
                visible.length +
                (overflowCount > 0 ? 1 : 0) +
                (showInviteCircle ? 1 : 0);

            const avatarSize = 30.0;
            const step = 20.0;
            final stackWidth = totalCircles > 0
                ? ((totalCircles - 1) * step) + avatarSize
                : avatarSize;

            return Row(
              children: [
                SizedBox(
                  key: const Key('profile_family_avatar_stack'),
                  width: stackWidth,
                  height: avatarSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        Positioned(
                          left: i * step,
                          child: MemberCircleAvatar(
                            displayName: visible[i].displayName,
                            seedKey:
                                '${visible[i].id}-${visible[i].displayName}',
                            size: avatarSize,
                            ringColor: heroBgRing,
                            ringWidth: 2.0,
                          ),
                        ),
                      if (overflowCount > 0)
                        Positioned(
                          left: visible.length * step,
                          child: Container(
                            key: const Key('family_stack_overflow_badge'),
                            width: avatarSize,
                            height: avatarSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.16),
                              border: Border.all(color: heroBgRing, width: 2.0),
                            ),
                            child: Text(
                              '+$overflowCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      if (showInviteCircle)
                        Positioned(
                          left: visible.length * step,
                          child: GestureDetector(
                            onTap: onAddMember,
                            child: Container(
                              width: avatarSize,
                              height: avatarSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.16),
                                border: Border.all(
                                  color: heroBgRing,
                                  width: 2.0,
                                ),
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Family',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: Text(
                              '${members.length}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _memberSummaryText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManageMembers) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: InkWell(
                      key: const Key('profile_add_member_btn'),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      onTap: onAddMember,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Add',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VaultReadinessCard extends StatelessWidget {
  const _VaultReadinessCard({
    required this.profile,
    required this.readinessScore,
    required this.hasAccounts,
    required this.hasBudgets,
    required this.lockEnabled,
    required this.privacyEnabled,
    required this.auditing,
    required this.auditHealthy,
    required this.auditJournalCount,
    required this.onRunAudit,
    required this.onEnableLock,
    required this.onSetBudget,
  });

  final FinancialProfile profile;
  final int readinessScore;
  final bool hasAccounts;
  final bool hasBudgets;
  final bool lockEnabled;
  final bool privacyEnabled;
  final bool auditing;
  final bool? auditHealthy;
  final int? auditJournalCount;
  final VoidCallback onRunAudit;
  final VoidCallback onEnableLock;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final scoreColor = readinessScore >= 80
        ? cfo.income
        : readinessScore >= 55
        ? scheme.primary
        : cfo.warning;
    final tierLabel = readinessScore >= 80
        ? 'Fortified'
        : readinessScore >= 55
        ? 'Active'
        : 'Starter';

    return TactileColorBlock(
      key: const Key('profile_vault_readiness'),
      accent: scoreColor,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RadialScoreGauge(
                score: readinessScore,
                label: tierLabel,
                activeColor: scoreColor,
                secondaryColor: scheme.secondary,
                size: 80,
                strokeWidth: 7,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vault Security & Readiness',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auditHealthy == true
                          ? 'Verified • ${auditJournalCount ?? 0} journal(s) balanced'
                          : 'AES-256 SQLite vault with double-entry audit',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: auditHealthy == true
                            ? cfo.income
                            : cfo.subtleText,
                        fontWeight: auditHealthy == true
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _ReadinessPill(label: 'AES-256', done: true, cfo: cfo),
                        _ReadinessPill(
                          label: 'Accounts',
                          done: hasAccounts,
                          cfo: cfo,
                        ),
                        _ReadinessPill(
                          label: 'Budget Guard',
                          done: hasBudgets,
                          cfo: cfo,
                          onTap: hasBudgets ? null : onSetBudget,
                        ),
                        _ReadinessPill(
                          label: 'App Lock',
                          done: lockEnabled,
                          cfo: cfo,
                          onTap: lockEnabled ? null : onEnableLock,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final btnFg = auditHealthy == true
                        ? Colors.white
                        : (isDark ? const Color(0xFF08142B) : Colors.white);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: auditHealthy == true
                              ? [cfo.income, const Color(0xFF059669)]
                              : (isDark
                                    ? const [
                                        Color(0xFFEBC974),
                                        Color(0xFFCFA03B),
                                      ]
                                    : const [
                                        Color(0xFF0E2554),
                                        Color(0xFF1A438F),
                                      ]),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(
                            0xFFE5C169,
                          ).withValues(alpha: isDark ? 0.50 : 0.34),
                          width: 0.9,
                        ),
                      ),
                      child: FilledButton.icon(
                        key: const Key('profile_run_audit_btn'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: btnFg,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: auditing ? null : onRunAudit,
                        icon: auditing
                            ? SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: btnFg,
                                ),
                              )
                            : Icon(
                                auditHealthy == true
                                    ? Icons.verified_rounded
                                    : Icons.fact_check_outlined,
                                size: 17,
                                color: auditHealthy == true
                                    ? Colors.white
                                    : (isDark
                                          ? const Color(0xFF08142B)
                                          : const Color(0xFFF5DA91)),
                              ),
                        label: Text(
                          auditHealthy == true
                              ? 'Ledger Balanced (${auditJournalCount ?? 0})'
                              : 'Verify Ledger Integrity',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadinessPill extends StatelessWidget {
  const _ReadinessPill({
    required this.label,
    required this.done,
    required this.cfo,
    this.onTap,
  });

  final String label;
  final bool done;
  final PocketCfoColors cfo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = done ? cfo.income : cfo.subtleText;
    final bg = done ? cfo.incomeContainer : cfo.surfaceTonal;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      onTap: onTap,
      child: chip,
    );
  }
}

class _VaultRosterRow extends StatelessWidget {
  const _VaultRosterRow({
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
  });

  final FinancialProfile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.32)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            ProfileAvatar(profile: profile, size: 38, selectedRing: isSelected),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${profile.baseCurrencyCode} • ${profile.profileType.label} • ${profile.role.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Active',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            else
              Icon(Icons.swap_horiz_rounded, size: 18, color: cfo.subtleText),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              IconButton(
                key: Key('roster_edit_${profile.id.value}'),
                tooltip: 'Edit ${profile.name}',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: scheme.primary,
                ),
                onPressed: onEdit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinanceSectionsGrid extends StatelessWidget {
  const _FinanceSectionsGrid({
    required this.cfo,
    required this.scheme,
    required this.budgetsCount,
    required this.pendingSyncCount,
  });

  final PocketCfoColors cfo;
  final ColorScheme scheme;
  final int budgetsCount;
  final int pendingSyncCount;

  @override
  Widget build(BuildContext context) {
    final sections = [
      (
        icon: Icons.pie_chart_rounded,
        label: 'Budgets',
        sub: budgetsCount > 0
            ? (budgetsCount == 1
                  ? '1 guard • CA BvA'
                  : '$budgetsCount guards • CA BvA')
            : 'CA ZBB & BvA',
        badge: budgetsCount > 0 ? '$budgetsCount' : null,
        route: '/budgets',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.savings_rounded,
        label: 'Savings Goals',
        sub: 'Target milestones',
        badge: null,
        route: '/goals',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.request_quote_rounded,
        label: 'Loans & EMI',
        sub: 'EMI & schedules',
        badge: null,
        route: '/loans',
        fg: cfo.warning,
        bg: cfo.warningContainer,
      ),
      (
        icon: Icons.repeat_rounded,
        label: 'Recurring',
        sub: 'Scheduled bills',
        badge: null,
        route: '/recurring',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
      (
        icon: Icons.category_rounded,
        label: 'Categories',
        sub: 'Income & spend',
        badge: null,
        route: '/categories',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.upload_file_rounded,
        label: 'CSV Import',
        sub: 'Statement mapper',
        badge: null,
        route: '/import-csv',
        fg: scheme.secondary,
        bg: scheme.secondaryContainer,
      ),
      (
        icon: Icons.cloud_sync_rounded,
        label: 'Cloud Sync',
        sub: pendingSyncCount > 0
            ? '$pendingSyncCount queued'
            : 'Multi-device sync',
        badge: pendingSyncCount > 0 ? '$pendingSyncCount' : null,
        route: '/sync',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.shield_rounded,
        label: 'Vault Backup',
        sub: 'Encrypted .pcfo',
        badge: null,
        route: '/backup',
        fg: cfo.success,
        bg: cfo.successContainer,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= AppBreakpoints.medium ? 4 : 2;
        const gap = AppSpacing.sm;
        final width = (constraints.maxWidth - (gap * (cols - 1))) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in sections)
              SizedBox(
                width: width,
                child: SculptedBentoAppTile(
                  icon: s.icon,
                  title: s.label,
                  subtitle: s.sub,
                  accent: s.fg,
                  badge: s.badge,
                  onTap: () => context.push(s.route),
                ),
              ),
          ],
        );
      },
    );
  }
}
