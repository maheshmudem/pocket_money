import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../core/utilities/profile_scope_controller.dart';
import '../../../budgets/domain/entities/budget_entity.dart';
import '../../../budgets/domain/repositories/budget_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/analytics_repository.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();
  @override
  List<Object?> get props => [];
}

final class DashboardRefreshRequested extends DashboardEvent {
  const DashboardRefreshRequested({this.period});
  final DashboardPeriodPreset? period;
  @override
  List<Object?> get props => [period];
}

final class _DashboardScopeChanged extends DashboardEvent {
  const _DashboardScopeChanged(this.snapshot);
  final ProfileScopeSnapshot snapshot;
  @override
  List<Object?> get props => [snapshot];
}

enum DashboardStatus { initial, loading, loaded, empty, failure }

final class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.period = DashboardPeriodPreset.thisMonth,
    this.summary,
    this.budgets = const [],
    this.scopeEpoch = 0,
    this.isRefreshing = false,
    this.failure,
  });

  final DashboardStatus status;
  final DashboardPeriodPreset period;
  final DashboardSummary? summary;
  final List<BudgetEntity> budgets;
  final int scopeEpoch;
  final bool isRefreshing;
  final AppFailure? failure;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardPeriodPreset? period,
    DashboardSummary? summary,
    bool clearSummary = false,
    List<BudgetEntity>? budgets,
    int? scopeEpoch,
    bool? isRefreshing,
    AppFailure? failure,
    bool clearFailure = false,
  }) => DashboardState(
    status: status ?? this.status,
    period: period ?? this.period,
    summary: clearSummary ? null : (summary ?? this.summary),
    budgets: budgets ?? this.budgets,
    scopeEpoch: scopeEpoch ?? this.scopeEpoch,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  @override
  List<Object?> get props => [
    status,
    period,
    summary,
    budgets,
    scopeEpoch,
    isRefreshing,
    failure,
  ];
}

/// Coordinates Dashboard period selection & profile-scoped aggregates (`SCR-DASH-001`).
/// Uses `restartable()` + epoch guard so late async responses from an old profile
/// can never leak into the active profile (`TC-FIN-017`).
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({
    required AnalyticsRepository analyticsRepository,
    required ProfileScopeController scopeController,
    BudgetRepository? budgetRepository,
  }) : _repo = analyticsRepository,
       _budgetRepo = budgetRepository,
       _scope = scopeController,
       super(const DashboardState()) {
    on<DashboardRefreshRequested>(_onRefresh, transformer: restartable());
    on<_DashboardScopeChanged>(_onScopeChanged, transformer: restartable());

    _scopeSub = _scope.stream.listen((snap) {
      add(_DashboardScopeChanged(snap));
    });
  }

  final AnalyticsRepository _repo;
  final BudgetRepository? _budgetRepo;
  final ProfileScopeController _scope;
  late final StreamSubscription<ProfileScopeSnapshot> _scopeSub;

  Future<void> _onScopeChanged(
    _DashboardScopeChanged event,
    Emitter<DashboardState> emit,
  ) async {
    // Immediately clear stale previous-profile summary before loading target profile.
    emit(
      DashboardState(
        status: event.snapshot.hasActiveProfile
            ? DashboardStatus.loading
            : DashboardStatus.empty,
        period: state.period,
        scopeEpoch: event.snapshot.epoch,
      ),
    );
    if (event.snapshot.hasActiveProfile) {
      await _loadForCurrentScope(emit, state.period);
    }
  }

  Future<void> _onRefresh(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    final targetPeriod = event.period ?? state.period;
    if (!_scope.current.hasActiveProfile) {
      emit(
        DashboardState(
          status: DashboardStatus.empty,
          period: targetPeriod,
          scopeEpoch: _scope.currentEpoch,
        ),
      );
      return;
    }

    final preserveCache =
        state.summary != null &&
        state.scopeEpoch == _scope.currentEpoch &&
        state.summary!.profileId == _scope.current.profileId;

    emit(
      state.copyWith(
        status: preserveCache
            ? DashboardStatus.loaded
            : DashboardStatus.loading,
        period: targetPeriod,
        isRefreshing: true,
        clearFailure: true,
      ),
    );
    await _loadForCurrentScope(emit, targetPeriod);
  }

  Future<void> _loadForCurrentScope(
    Emitter<DashboardState> emit,
    DashboardPeriodPreset period,
  ) async {
    final capturedEpoch = _scope.currentEpoch;
    final ProfileId? capturedProfile = _scope.current.profileId;
    if (capturedProfile == null) return;

    final res = await _repo.computeDashboardSummary(
      capturedProfile,
      period: period,
    );
    final budgetsRes = await _budgetRepo?.listBudgetsWithProgress(
      capturedProfile,
    );

    // TC-FIN-017: Discard late response if profile switched while query was in flight!
    if (!_scope.isCurrentEpoch(capturedEpoch, capturedProfile)) {
      return;
    }

    final budgets = budgetsRes?.valueOrNull ?? const <BudgetEntity>[];

    res.fold(
      onSuccess: (summary) {
        final isEmpty =
            summary.accounts.isEmpty &&
            summary.recentTransactions.isEmpty &&
            budgets.isEmpty;
        emit(
          DashboardState(
            status: isEmpty ? DashboardStatus.empty : DashboardStatus.loaded,
            period: period,
            summary: summary,
            budgets: budgets,
            scopeEpoch: capturedEpoch,
            isRefreshing: false,
          ),
        );
      },
      onFailure: (f) {
        emit(
          state.copyWith(
            status: state.summary != null
                ? DashboardStatus.loaded
                : DashboardStatus.failure,
            isRefreshing: false,
            failure: f,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    await _scopeSub.cancel();
    return super.close();
  }
}
