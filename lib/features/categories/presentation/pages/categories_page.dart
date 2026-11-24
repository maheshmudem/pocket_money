import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';

/// `SCR-CAT-001` — Profile-scoped system and custom categories mapped to ledger accounts.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  CategoryType _filterType = CategoryType.expense;
  ProfileId? _watchedProfileId;
  Stream<List<CategoryEntity>>? _categoriesStream;

  Stream<List<CategoryEntity>> _streamFor(
    CategoryRepository repo,
    ProfileId profileId,
  ) {
    if (_watchedProfileId != profileId || _categoriesStream == null) {
      _watchedProfileId = profileId;
      _categoriesStream = repo.watchCategories(
        profileId,
        includeInactive: true,
      );
    }
    return _categoriesStream!;
  }

  IconData _iconForCategory(String name, CategoryType type) {
    final lower = name.toLowerCase();
    if (lower.contains('food') || lower.contains('dining')) {
      return Icons.restaurant_rounded;
    }
    if (lower.contains('grocer')) return Icons.local_grocery_store_rounded;
    if (lower.contains('rent') || lower.contains('hous')) {
      return Icons.home_rounded;
    }
    if (lower.contains('travel') || lower.contains('transport')) {
      return Icons.directions_car_rounded;
    }
    if (lower.contains('health') || lower.contains('med')) {
      return Icons.favorite_rounded;
    }
    if (lower.contains('shop')) return Icons.shopping_bag_rounded;
    if (lower.contains('salary') || lower.contains('income')) {
      return Icons.payments_rounded;
    }
    if (lower.contains('util') || lower.contains('bill')) {
      return Icons.bolt_rounded;
    }
    return type == CategoryType.income
        ? Icons.south_west_rounded
        : Icons.label_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.category_outlined,
          title: 'No active profile',
          description: 'Select a profile to manage its categories.',
        ),
      );
    }

    final repo = GetIt.I<CategoryRepository>();
    final cfo = context.cfoColors;
    final canManage = profile.permissions.canManageCategoriesAndBudgets;

    return Scaffold(
      appBar: const EnterpriseAppBar(title: Text('Categories')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openAddCategorySheet(context, profile.id, repo),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Category'),
            )
          : null,
      body: StreamBuilder<List<CategoryEntity>>(
        stream: _streamFor(repo, profile.id),
        builder: (context, snap) {
          final cats = snap.data ?? const [];
          if (cats.isEmpty) {
            return EmptyStateView(
              icon: Icons.category_outlined,
              title: 'No categories found',
              description: 'Add custom income or expense categories.',
              actionLabel: canManage ? 'New Category' : null,
              onAction: canManage
                  ? () => _openAddCategorySheet(context, profile.id, repo)
                  : null,
            );
          }

          final expenseCount = cats
              .where((c) => c.categoryType == CategoryType.expense)
              .length;
          final incomeCount = cats
              .where((c) => c.categoryType == CategoryType.income)
              .length;
          final filtered = cats
              .where((c) => c.categoryType == _filterType)
              .toList();

          return SingleChildScrollView(
            padding: EnterprisePageContainer.responsivePadding(
              context,
              bottom: 96,
            ),
            child: EnterprisePageContainer(
              maxWidth: AppBreakpoints.maxContentWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoCols = constraints.maxWidth >= 680;
                  final cardWidth = twoCols
                      ? (constraints.maxWidth - AppSpacing.sm) / 2
                      : constraints.maxWidth;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FintechSegmentedControl<CategoryType>(
                        key: const Key('categories_segmented_filter'),
                        selected: _filterType,
                        options: [
                          FintechSegmentOption(
                            value: CategoryType.expense,
                            label: 'Expense',
                            icon: Icons.north_east_rounded,
                            badgeCount: expenseCount,
                          ),
                          FintechSegmentOption(
                            value: CategoryType.income,
                            label: 'Income',
                            icon: Icons.south_west_rounded,
                            badgeCount: incomeCount,
                          ),
                        ],
                        onChanged: (t) => setState(() => _filterType = t),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionHeader(
                        title:
                            '${_filterType.label} Categories (${filtered.length})',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (var i = 0; i < filtered.length; i++)
                            SizedBox(
                              width: cardWidth,
                              child: Builder(
                                builder: (context) {
                                  final c = filtered[i];
                                  final isIncome =
                                      c.categoryType == CategoryType.income;
                                  return StaggeredFadeSlide(
                                    index: i,
                                    child: PressScaleCard(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                        vertical: AppSpacing.xs,
                                      ),
                                      child: Row(
                                        children: [
                                          IconSquircle(
                                            icon: _iconForCategory(
                                              c.name,
                                              c.categoryType,
                                            ),
                                            iconColor: isIncome
                                                ? cfo.income
                                                : cfo.expense,
                                            backgroundColor: isIncome
                                                ? cfo.incomeContainer
                                                : cfo.expenseContainer,
                                            size: 40,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  c.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleSmall,
                                                ),
                                                Text(
                                                  c.isSystem
                                                      ? 'Built-in system category'
                                                      : 'Custom category',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: cfo.subtleText,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: c.isActive,
                                            onChanged: canManage
                                                ? (active) =>
                                                      repo.updateCategory(
                                                        profileId: profile.id,
                                                        categoryId: c.id,
                                                        name: c.name,
                                                        isActive: active,
                                                      )
                                                : null,
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
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAddCategorySheet(
    BuildContext context,
    ProfileId profileId,
    CategoryRepository repo,
  ) async {
    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 460,
      builder: (_) => _AddCategorySheetBody(
        profileId: profileId,
        repo: repo,
        initialType: _filterType,
      ),
    );
  }
}

class _AddCategorySheetBody extends StatefulWidget {
  const _AddCategorySheetBody({
    required this.profileId,
    required this.repo,
    required this.initialType,
  });

  final ProfileId profileId;
  final CategoryRepository repo;
  final CategoryType initialType;

  @override
  State<_AddCategorySheetBody> createState() => _AddCategorySheetBodyState();
}

class _AddCategorySheetBodyState extends State<_AddCategorySheetBody> {
  final _nameCtrl = TextEditingController();
  late CategoryType _type;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseModalHeader(
                title: 'New Category',
                subtitle: 'Scoped strictly to this profile ledger.',
                icon: Icons.category_rounded,
              ),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: cfo.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(
                      color: cfo.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FintechTextField(
                label: 'Category Name',
                controller: _nameCtrl,
                leadingIcon: Icons.local_offer_outlined,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
                autofocus: true,
                onChanged: (_) => setState(() => _errorMsg = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<CategoryType>(
                label: 'Type',
                value: _type,
                leadingIcon: Icons.category_outlined,
                options: [
                  FintechDropdownOption<CategoryType>(
                    value: CategoryType.expense,
                    label: CategoryType.expense.label,
                    subtitle: 'Tracks outflows & spending caps',
                    icon: Icons.arrow_upward_rounded,
                    iconColor: cfo.expense,
                    iconBackground: cfo.expenseContainer,
                  ),
                  FintechDropdownOption<CategoryType>(
                    value: CategoryType.income,
                    label: CategoryType.income.label,
                    subtitle: 'Tracks salary, freelance & inflows',
                    icon: Icons.arrow_downward_rounded,
                    iconColor: cfo.income,
                    iconBackground: cfo.incomeContainer,
                  ),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(
                            () => _errorMsg = 'Please enter a category name.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final res = await widget.repo.createCategory(
                          profileId: widget.profileId,
                          name: _nameCtrl.text.trim(),
                          categoryType: _type,
                        );
                        if (!context.mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg = res.failureOrNull!.message;
                          });
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                child: const Text('Save Category'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
