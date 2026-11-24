import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../authentication/presentation/bloc/auth_cubit.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../bloc/active_profile_cubit.dart';

Future<void> openCreateProfileModal(
  BuildContext context, {
  ProfileType presetType = ProfileType.personal,
  String suggestedName = '',
}) async {
  await showModernDialog<void>(
    context: context,
    builder: (_) => _CreateProfileDialog(
      presetType: presetType,
      suggestedName: suggestedName,
      parentContext: context,
    ),
  );
}

/// Reusable modal for viewing, adding, and managing Family / Profile Members (`SCR-PRO-003`).
Future<void> openProfileMembersModal(
  BuildContext context,
  FinancialProfile profile, {
  VoidCallback? onUpdated,
}) async {
  final repo = GetIt.I<ProfileRepository>();
  final userId = context.read<AuthCubit>().state.user?.id ?? 'local-owner';
  final res = await repo.listMembers(
    profileId: profile.id,
    requestingUserId: userId,
  );
  if (!context.mounted) return;
  final initialMembers = (res.valueOrNull ?? const <ProfileMember>[])
      .where((m) => m.status == 'active')
      .toList();

  await showEnterpriseModal<void>(
    context: context,
    maxWidth: 500,
    builder: (sheetCtx) => _FamilyMembersSheetBody(
      profile: profile,
      requestingUserId: userId,
      initialMembers: initialMembers,
      onUpdated: onUpdated,
    ),
  );
}

/// Reusable dialog for adding a Family / Profile Member directly.
Future<void> openAddFamilyMemberDialog(
  BuildContext context,
  FinancialProfile profile, {
  VoidCallback? onSaved,
}) async {
  final userId = context.read<AuthCubit>().state.user?.id ?? 'local-owner';
  await showModernDialog<void>(
    context: context,
    builder: (_) => _InviteMemberDialog(
      profile: profile,
      requestingUserId: userId,
      onSaved: onSaved,
    ),
  );
}

/// Covers `SCR-PRO-001` (Profile Selector), `SCR-PRO-002` (Create/Edit Profile),
/// and `SCR-PRO-003` (Members & Roles RBAC).
class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key, this.isInitialSetup = false});

  final bool isInitialSetup;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<ActiveProfileCubit, ActiveProfileState>(
      builder: (context, state) {
        final hasProfiles = state.profiles.isNotEmpty;

        return Scaffold(
          appBar: EnterpriseAppBar(
            title: Text(
              isInitialSetup
                  ? 'Create Your First Profile'
                  : 'Financial Profiles',
            ),
            actions: const [
              ThemeQuickToggleButton(),
              SizedBox(width: AppSpacing.xs),
            ],
          ),
          floatingActionButton: hasProfiles
              ? FloatingActionButton.extended(
                  onPressed: () => _openCreateProfileDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Profile'),
                )
              : null,
          body: Builder(
            builder: (context) {
              if (state.status == ActiveProfileStatus.loading) {
                return const DashboardSkeletonView();
              }
              if (!hasProfiles) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StaggeredFadeSlide(
                            index: 0,
                            child: Column(
                              children: [
                                const PocketCfoLogo(
                                  size: 56,
                                  animateEntrance: true,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Design your financial workspace',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'Keep personal, family, and business accounts isolated in dedicated vaults — pick a quick template or create custom.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: cfo.subtleText),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: () => _openCreateProfileDialog(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create Profile'),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'QUICK-START TEMPLATES',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _ProfileTemplateTile(
                            index: 1,
                            icon: Icons.person_rounded,
                            iconColor: scheme.primary,
                            iconBg: scheme.primaryContainer,
                            title: 'Personal Wealth',
                            subtitle:
                                'Salary, cards, expenses & private savings goals',
                            onTap: () => _openCreateProfileDialog(
                              context,
                              presetType: ProfileType.personal,
                              suggestedName: 'Personal Finance',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _ProfileTemplateTile(
                            index: 2,
                            icon: Icons.family_restroom_rounded,
                            iconColor: cfo.income,
                            iconBg: cfo.incomeContainer,
                            title: 'Family & Home',
                            subtitle:
                                'Shared household bills, groceries & family budgets',
                            onTap: () => _openCreateProfileDialog(
                              context,
                              presetType: ProfileType.family,
                              suggestedName: 'Household Vault',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _ProfileTemplateTile(
                            index: 3,
                            icon: Icons.business_center_rounded,
                            iconColor: cfo.transfer,
                            iconBg: cfo.transferContainer,
                            title: 'Business & Studio',
                            subtitle:
                                'Operating cash flow, loans, retainers & GST-ready export',
                            onTap: () => _openCreateProfileDialog(
                              context,
                              presetType: ProfileType.business,
                              suggestedName: 'Business Ledger',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return EnterprisePageContainer(
                maxWidth: AppBreakpoints.maxReadingWidth,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final padding = EnterprisePageContainer.responsivePadding(
                      context,
                      bottom: 96,
                    );
                    final innerWidth =
                        constraints.maxWidth - padding.horizontal;
                    final twoCols = innerWidth >= 680;
                    final tileWidth = twoCols
                        ? (innerWidth - AppSpacing.sm) / 2
                        : innerWidth;

                    return SingleChildScrollView(
                      padding: padding,
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (
                            var index = 0;
                            index < state.profiles.length;
                            index++
                          )
                            SizedBox(
                              width: tileWidth,
                              child: Builder(
                                builder: (context) {
                                  final profile = state.profiles[index];
                                  final isSelected =
                                      state.activeProfile?.id == profile.id;
                                  return StaggeredFadeSlide(
                                    index: index,
                                    child: PressScaleCard(
                                      onTap: () => context
                                          .read<ActiveProfileCubit>()
                                          .switchProfile(profile.id),
                                      borderColor: isSelected
                                          ? scheme.primary
                                          : cfo.divider,
                                      backgroundColor: isSelected
                                          ? scheme.primaryContainer.withValues(
                                              alpha: 0.35,
                                            )
                                          : cfo.surfaceElevated,
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Row(
                                        children: [
                                          IconSquircle(
                                            icon: switch (profile.profileType) {
                                              ProfileType.personal =>
                                                Icons.person_rounded,
                                              ProfileType.family =>
                                                Icons.family_restroom_rounded,
                                              ProfileType.business =>
                                                Icons.business_center_rounded,
                                            },
                                            iconColor: isSelected
                                                ? scheme.onPrimary
                                                : scheme.primary,
                                            backgroundColor: isSelected
                                                ? scheme.primary
                                                : scheme.primaryContainer,
                                            size: 48,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        profile.name,
                                                        style: Theme.of(
                                                          context,
                                                        ).textTheme.titleMedium,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (isSelected)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: scheme.primary,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                AppSpacing
                                                                    .radiusFull,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'Active',
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                                color: scheme
                                                                    .onPrimary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${profile.profileType.label} • ${profile.baseCurrencyCode}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color:
                                                                cfo.subtleText,
                                                          ),
                                                    ),
                                                    Text(
                                                      'Role: ${profile.role.label}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color:
                                                                cfo.subtleText,
                                                          ),
                                                    ),
                                                    SyncStatusBadge(
                                                      status:
                                                          profile.syncStatus,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (action) {
                                              if (action == 'switch') {
                                                context
                                                    .read<ActiveProfileCubit>()
                                                    .switchProfile(profile.id);
                                              } else if (action == 'members') {
                                                _openMembersSheet(
                                                  context,
                                                  profile,
                                                );
                                              } else if (action == 'currency') {
                                                _openBaseCurrencyDialog(
                                                  context,
                                                  profile,
                                                );
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'switch',
                                                child: Text(
                                                  'Switch to profile',
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'members',
                                                child: Text('Members & roles'),
                                              ),
                                              if (profile
                                                  .permissions
                                                  .canChangeSettingsOrCurrency)
                                                const PopupMenuItem(
                                                  value: 'currency',
                                                  child: Text(
                                                    'Change base currency',
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openCreateProfileDialog(
    BuildContext context, {
    ProfileType presetType = ProfileType.personal,
    String suggestedName = '',
  }) => openCreateProfileModal(
    context,
    presetType: presetType,
    suggestedName: suggestedName,
  );

  Future<void> _openBaseCurrencyDialog(
    BuildContext context,
    FinancialProfile profile,
  ) async {
    var nextCode = profile.baseCurrencyCode;
    await showModernDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          final cfo = ctx.cfoColors;
          return ModernDialogShell(
            title: 'Change Base Currency',
            subtitle: 'Applies to future summaries and reporting',
            icon: Icons.currency_exchange_rounded,
            confirmLabel: 'Confirm Change',
            onConfirm: () async {
              HapticFeedback.selectionClick();
              await context
                  .read<ActiveProfileCubit>()
                  .changeProfileBaseCurrency(
                    profileId: profile.id,
                    newCurrencyCode: nextCode,
                  );
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: cfo.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: cfo.divider.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Text(
                    'Historical posted transactions preserve their original FX snapshots and base amounts. New reports use the updated base currency from today forward.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cfo.subtleText,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FintechDropdownField<String>(
                  label: 'New Base Currency',
                  value: nextCode,
                  leadingIcon: Icons.currency_exchange_rounded,
                  searchable: true,
                  searchHint: 'Search currency...',
                  options: FintechDropdownOption.builtInCurrencies(),
                  onChanged: (v) => setState(() => nextCode = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openMembersSheet(
    BuildContext context,
    FinancialProfile profile,
  ) => openProfileMembersModal(context, profile);
}

class _FamilyMembersSheetBody extends StatefulWidget {
  const _FamilyMembersSheetBody({
    required this.profile,
    required this.requestingUserId,
    required this.initialMembers,
    this.onUpdated,
  });

  final FinancialProfile profile;
  final String requestingUserId;
  final List<ProfileMember> initialMembers;
  final VoidCallback? onUpdated;

  @override
  State<_FamilyMembersSheetBody> createState() =>
      _FamilyMembersSheetBodyState();
}

class _FamilyMembersSheetBodyState extends State<_FamilyMembersSheetBody> {
  late List<ProfileMember> _members;

  @override
  void initState() {
    super.initState();
    _members = widget.initialMembers;
  }

  Future<void> _refresh() async {
    final res = await GetIt.I<ProfileRepository>().listMembers(
      profileId: widget.profile.id,
      requestingUserId: widget.requestingUserId,
    );
    if (!mounted) return;
    setState(() {
      _members = (res.valueOrNull ?? const <ProfileMember>[])
          .where((m) => m.status == 'active')
          .toList();
    });
    widget.onUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final profile = widget.profile;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnterpriseModalHeader(
                title: 'Family Members — ${profile.name}',
                subtitle:
                    '${_members.length} active member(s) • Roles are scoped strictly to this profile.',
                icon: Icons.groups_rounded,
              ),
              for (final m in _members) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      MemberCircleAvatar(
                        displayName: m.displayName,
                        seedKey: '${m.id}-${m.displayName}',
                        size: 38,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              m.email?.isNotEmpty == true
                                  ? m.email!
                                  : m.role.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cfo.subtleText),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FintechStatusPill(
                        label: m.role.label,
                        foreground: m.role == ProfileRole.owner
                            ? scheme.primary
                            : scheme.onSurface,
                        background: m.role == ProfileRole.owner
                            ? scheme.primaryContainer
                            : cfo.surfaceTonal,
                      ),
                      if (profile.permissions.canManageMembers &&
                          m.role != ProfileRole.owner) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Remove member',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.person_remove_outlined,
                            size: 18,
                            color: cfo.expense,
                          ),
                          onPressed: () async {
                            final confirmed = await showModernConfirmDialog(
                              context: context,
                              title: 'Remove ${m.displayName}?',
                              subtitle: 'Access to ${profile.name} will end',
                              icon: Icons.person_remove_outlined,
                              accent: ModernDialogAccent.danger,
                              confirmLabel: 'Remove',
                              message:
                                  'Historical entries remain intact, and you can re-invite this member anytime.',
                            );
                            if (confirmed != true) return;
                            await GetIt.I<ProfileRepository>().revokeMember(
                              profileId: profile.id,
                              requestingUserId: widget.requestingUserId,
                              memberId: m.id,
                            );
                            await _refresh();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: cfo.divider),
              ],
              const SizedBox(height: AppSpacing.md),
              if (profile.permissions.canManageMembers)
                FilledButton.icon(
                  key: const Key('members_sheet_add_btn'),
                  onPressed: () async {
                    await showModernDialog<void>(
                      context: context,
                      builder: (_) => _InviteMemberDialog(
                        profile: profile,
                        requestingUserId: widget.requestingUserId,
                        onSaved: _refresh,
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add Family Member'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog({
    required this.presetType,
    required this.suggestedName,
    required this.parentContext,
  });

  final ProfileType presetType;
  final String suggestedName;
  final BuildContext parentContext;

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  late final TextEditingController _nameCtrl;
  late ProfileType _selectedType;
  String _selectedCurrency = CurrencyCatalog.defaultCurrencyCode;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.suggestedName);
    _selectedType = widget.presetType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = widget.parentContext.read<AuthCubit>().state.user;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final previewName = _nameCtrl.text.trim().isEmpty
        ? 'New Vault'
        : _nameCtrl.text.trim();
    final previewProfile = FinancialProfile(
      id: const ProfileId('preview'),
      name: previewName,
      profileType: _selectedType,
      baseCurrencyCode: _selectedCurrency,
      timezone: 'UTC',
      role: ProfileRole.owner,
      editorsCanPost: true,
      createdAtUtc: '',
      updatedAtUtc: '',
      version: 1,
      syncStatus: 'local_only',
    );

    return ModernDialogShell(
      title: 'Create Financial Profile',
      subtitle: 'Isolated double-entry vault with its own ledger & budgets',
      icon: Icons.add_business_rounded,
      confirmLabel: 'Create Profile',
      isConfirmLoading: _submitting,
      onConfirm: () async {
        if (_nameCtrl.text.trim().isEmpty) return;
        setState(() => _submitting = true);
        HapticFeedback.selectionClick();
        final cubit = widget.parentContext.read<ActiveProfileCubit>();
        final messenger = ScaffoldMessenger.of(widget.parentContext);
        final nav = Navigator.of(context);
        final dialogRoute = ModalRoute.of(context);
        final res = await cubit.createProfile(
          ownerDisplayName: authUser?.displayName ?? 'Owner',
          ownerEmail: authUser?.email,
          name: _nameCtrl.text,
          profileType: _selectedType,
          baseCurrencyCode: _selectedCurrency,
          queueSync: !(authUser?.isLocalOnlyWorkspace ?? true),
        );
        if (mounted && (dialogRoute?.isCurrent ?? false) && nav.canPop()) {
          nav.pop();
        }
        if (res.isFailure) {
          messenger.showSnackBar(
            SnackBar(content: Text(res.failureOrNull!.message)),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                ProfileAvatar(
                  profile: previewProfile,
                  size: 36,
                  showTypeBadge: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        previewName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_selectedType.label} • $_selectedCurrency',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ),
                ),
                FintechStatusPill(
                  label: _selectedCurrency,
                  foreground: scheme.primary,
                  background: scheme.primaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FintechTextField(
            label: 'Profile Name (e.g., Personal, Household, Studio)',
            controller: _nameCtrl,
            leadingIcon: Icons.badge_outlined,
            textCapitalization: TextCapitalization.words,
            showClearButton: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Text(
            'Profile Type',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cfo.subtleText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ProfileType.values.map((t) {
              return ChoiceChip(
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                label: Text(t.label),
                selected: _selectedType == t,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedType = t);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          FintechDropdownField<String>(
            key: const Key('create_profile_currency_dropdown'),
            label: 'Base Currency',
            value: _selectedCurrency,
            leadingIcon: Icons.payments_outlined,
            searchable: true,
            searchHint: 'Search currency...',
            options: FintechDropdownOption.builtInCurrencies(),
            onChanged: (v) => setState(() => _selectedCurrency = v),
          ),
        ],
      ),
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({
    required this.profile,
    required this.requestingUserId,
    this.onSaved,
  });

  final FinancialProfile profile;
  final String requestingUserId;
  final VoidCallback? onSaved;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  ProfileRole _role = ProfileRole.editor;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final previewName = _nameCtrl.text.trim().isEmpty
        ? 'New Member'
        : _nameCtrl.text.trim();

    return ModernDialogShell(
      title: 'Add Family Member',
      subtitle: 'Grant role-based access to ${widget.profile.name}',
      icon: Icons.group_add_rounded,
      confirmLabel: 'Add Member',
      isConfirmLoading: _submitting,
      onConfirm: () async {
        final name = _nameCtrl.text.trim();
        final email = _emailCtrl.text.trim().toLowerCase();
        if (name.isEmpty && email.isEmpty) {
          setState(() => _errorMsg = 'Please enter a family member name.');
          return;
        }
        setState(() {
          _submitting = true;
          _errorMsg = null;
        });
        HapticFeedback.selectionClick();
        final nav = Navigator.of(context);
        final dialogRoute = ModalRoute.of(context);
        final memberUserId = email.isNotEmpty
            ? email
            : 'family-${GetIt.I<IdGenerator>().nextUuid()}';
        await GetIt.I<ProfileRepository>().addOrUpdateMember(
          profileId: widget.profile.id,
          requestingUserId: widget.requestingUserId,
          memberUserId: memberUserId,
          displayName: name.isNotEmpty ? name : email,
          email: email.isNotEmpty ? email : null,
          role: _role,
        );
        if (!mounted) return;
        widget.onSaved?.call();
        if ((dialogRoute?.isCurrent ?? false) && nav.canPop()) {
          nav.pop();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                MemberCircleAvatar(displayName: previewName, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        previewName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _role.label,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ),
                ),
                FintechStatusPill(
                  label: _role.label,
                  foreground: Theme.of(context).colorScheme.primary,
                  background: Theme.of(context).colorScheme.primaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cfo.expenseContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: cfo.expense,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cfo.expense,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          FintechTextField(
            label: 'Member Name (e.g., Mom, Priya, Arjun)',
            controller: _nameCtrl,
            leadingIcon: Icons.person_outline_rounded,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            showClearButton: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          FintechTextField(
            label: 'Email (optional)',
            controller: _emailCtrl,
            leadingIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            showClearButton: true,
          ),
          const SizedBox(height: 10),
          FintechDropdownField<ProfileRole>(
            key: const Key('invite_member_role_dropdown'),
            label: 'Profile Role',
            value: _role,
            leadingIcon: Icons.shield_outlined,
            options: const [
              FintechDropdownOption<ProfileRole>(
                value: ProfileRole.admin,
                label: 'Admin',
                subtitle: 'Manage accounts, budgets & members',
                icon: Icons.admin_panel_settings_outlined,
              ),
              FintechDropdownOption<ProfileRole>(
                value: ProfileRole.editor,
                label: 'Editor',
                subtitle: 'Record expenses, income & transfers',
                icon: Icons.edit_note_rounded,
              ),
              FintechDropdownOption<ProfileRole>(
                value: ProfileRole.viewer,
                label: 'Viewer',
                subtitle: 'Read-only access to balances & insights',
                icon: Icons.visibility_outlined,
              ),
            ],
            onChanged: (v) => setState(() => _role = v),
          ),
        ],
      ),
    );
  }
}

class _ProfileTemplateTile extends StatelessWidget {
  const _ProfileTemplateTile({
    required this.index,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StaggeredFadeSlide(
      index: index,
      child: PressScaleCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            IconSquircle(
              icon: icon,
              iconColor: iconColor,
              backgroundColor: iconBg,
              size: 46,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.cfoColors.subtleText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: context.cfoColors.subtleText,
            ),
          ],
        ),
      ),
    );
  }
}
