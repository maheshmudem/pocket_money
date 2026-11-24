import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../core/utilities/profile_scope_controller.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';

sealed class TransactionsEvent extends Equatable {
  const TransactionsEvent();
  @override
  List<Object?> get props => [];
}

final class TransactionsLoadRequested extends TransactionsEvent {
  const TransactionsLoadRequested({this.filter});
  final TransactionFilter? filter;
  @override
  List<Object?> get props => [filter];
}

final class TransactionsSearchChanged extends TransactionsEvent {
  const TransactionsSearchChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

final class TransactionsLoadMoreRequested extends TransactionsEvent {
  const TransactionsLoadMoreRequested();
}

final class _TransactionsScopeChanged extends TransactionsEvent {
  const _TransactionsScopeChanged(this.snapshot);
  final ProfileScopeSnapshot snapshot;
  @override
  List<Object?> get props => [snapshot];
}

enum TransactionsStatus { initial, loading, loaded, empty, failure }

final class TransactionsState extends Equatable {
  const TransactionsState({
    this.status = TransactionsStatus.initial,
    this.items = const [],
    this.totalCount = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.filter = const TransactionFilter(),
    this.scopeEpoch = 0,
    this.failure,
  });

  final TransactionsStatus status;
  final List<TransactionEntity> items;
  final int totalCount;
  final bool hasMore;
  final bool isLoadingMore;
  final TransactionFilter filter;
  final int scopeEpoch;
  final AppFailure? failure;

  TransactionsState copyWith({
    TransactionsStatus? status,
    List<TransactionEntity>? items,
    int? totalCount,
    bool? hasMore,
    bool? isLoadingMore,
    TransactionFilter? filter,
    int? scopeEpoch,
    AppFailure? failure,
    bool clearFailure = false,
  }) => TransactionsState(
    status: status ?? this.status,
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    filter: filter ?? this.filter,
    scopeEpoch: scopeEpoch ?? this.scopeEpoch,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  @override
  List<Object?> get props => [
    status,
    items,
    totalCount,
    hasMore,
    isLoadingMore,
    filter,
    scopeEpoch,
    failure,
  ];
}

class TransactionsBloc extends Bloc<TransactionsEvent, TransactionsState> {
  TransactionsBloc({
    required TransactionRepository repository,
    required ProfileScopeController scopeController,
    int pageSize = 40,
  }) : _repo = repository,
       _scope = scopeController,
       _pageSize = pageSize,
       super(const TransactionsState()) {
    on<TransactionsLoadRequested>(_onLoad, transformer: restartable());
    on<TransactionsSearchChanged>(_onSearch, transformer: restartable());
    on<TransactionsLoadMoreRequested>(_onLoadMore, transformer: droppable());
    on<_TransactionsScopeChanged>(_onScopeChanged, transformer: restartable());

    _scopeSub = _scope.stream.listen((snap) {
      add(_TransactionsScopeChanged(snap));
    });
  }

  final TransactionRepository _repo;
  final ProfileScopeController _scope;
  final int _pageSize;
  late final StreamSubscription<ProfileScopeSnapshot> _scopeSub;

  Future<void> _onScopeChanged(
    _TransactionsScopeChanged event,
    Emitter<TransactionsState> emit,
  ) async {
    emit(
      TransactionsState(
        status: event.snapshot.hasActiveProfile
            ? TransactionsStatus.loading
            : TransactionsStatus.empty,
        scopeEpoch: event.snapshot.epoch,
      ),
    );
    if (event.snapshot.hasActiveProfile) {
      await _fetchFirstPage(emit, const TransactionFilter());
    }
  }

  Future<void> _onLoad(
    TransactionsLoadRequested event,
    Emitter<TransactionsState> emit,
  ) async {
    final filter = event.filter ?? state.filter;
    emit(
      state.copyWith(
        status: TransactionsStatus.loading,
        filter: filter,
        clearFailure: true,
      ),
    );
    await _fetchFirstPage(emit, filter);
  }

  Future<void> _onSearch(
    TransactionsSearchChanged event,
    Emitter<TransactionsState> emit,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final nextFilter = TransactionFilter(
      searchQuery: event.query,
      accountId: state.filter.accountId,
      categoryId: state.filter.categoryId,
      type: state.filter.type,
      status: state.filter.status,
      fromUtc: state.filter.fromUtc,
      toUtc: state.filter.toUtc,
    );
    emit(state.copyWith(filter: nextFilter, clearFailure: true));
    await _fetchFirstPage(emit, nextFilter);
  }

  Future<void> _onLoadMore(
    TransactionsLoadMoreRequested event,
    Emitter<TransactionsState> emit,
  ) async {
    if (!state.hasMore || state.isLoadingMore) return;
    final capturedEpoch = _scope.currentEpoch;
    final ProfileId? profileId = _scope.current.profileId;
    if (profileId == null) return;

    emit(state.copyWith(isLoadingMore: true));
    final res = await _repo.queryTransactions(
      profileId,
      filter: state.filter,
      limit: _pageSize,
      offset: state.items.length,
    );
    if (!_scope.isCurrentEpoch(capturedEpoch, profileId)) return;

    res.fold(
      onSuccess: (page) => emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          totalCount: page.totalCount,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      ),
      onFailure: (f) => emit(state.copyWith(isLoadingMore: false, failure: f)),
    );
  }

  Future<void> _fetchFirstPage(
    Emitter<TransactionsState> emit,
    TransactionFilter filter,
  ) async {
    final capturedEpoch = _scope.currentEpoch;
    final ProfileId? profileId = _scope.current.profileId;
    if (profileId == null) {
      emit(
        TransactionsState(
          status: TransactionsStatus.empty,
          filter: filter,
          scopeEpoch: capturedEpoch,
        ),
      );
      return;
    }

    final res = await _repo.queryTransactions(
      profileId,
      filter: filter,
      limit: _pageSize,
      offset: 0,
    );
    if (!_scope.isCurrentEpoch(capturedEpoch, profileId)) return;

    res.fold(
      onSuccess: (page) => emit(
        TransactionsState(
          status: page.items.isEmpty
              ? TransactionsStatus.empty
              : TransactionsStatus.loaded,
          items: page.items,
          totalCount: page.totalCount,
          hasMore: page.hasMore,
          filter: filter,
          scopeEpoch: capturedEpoch,
        ),
      ),
      onFailure: (f) => emit(
        state.copyWith(
          status: TransactionsStatus.failure,
          failure: f,
          scopeEpoch: capturedEpoch,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _scopeSub.cancel();
    return super.close();
  }
}
