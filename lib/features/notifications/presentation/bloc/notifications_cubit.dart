import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/financial_engine/alert_evaluation_engine.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../core/utilities/profile_scope_controller.dart';
import '../../data/financial_alerts_coordinator.dart';

final class NotificationsState extends Equatable {
  const NotificationsState({
    this.unreadCount = 0,
    this.activeBanner,
    this.bannerSeq = 0,
    this.celebrationTick = 0,
  });

  final int unreadCount;
  final EvaluatedAlert? activeBanner;
  final int bannerSeq;
  final int celebrationTick;

  NotificationsState copyWith({
    int? unreadCount,
    EvaluatedAlert? activeBanner,
    bool clearBanner = false,
    int? bannerSeq,
    int? celebrationTick,
  }) => NotificationsState(
    unreadCount: unreadCount ?? this.unreadCount,
    activeBanner: clearBanner ? null : (activeBanner ?? this.activeBanner),
    bannerSeq: bannerSeq ?? this.bannerSeq,
    celebrationTick: celebrationTick ?? this.celebrationTick,
  );

  @override
  List<Object?> get props => [
    unreadCount,
    activeBanner,
    bannerSeq,
    celebrationTick,
  ];
}

/// Profile-scoped reactive notification & celebration state controller.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({
    required FinancialAlertsCoordinator coordinator,
    required ProfileScopeController scopeController,
  }) : _coordinator = coordinator,
       _scope = scopeController,
       super(const NotificationsState()) {
    _scopeSub = _scope.stream.listen(_onScopeChanged);
    _liveSub = _coordinator.liveAlerts.listen(_onLiveAlert);
    _inboxSub = _coordinator.inboxChanges.listen(_onInboxChanged);
    final current = _scope.current.profileId;
    if (current != null) {
      _activeProfileId = current;
      _refreshUnread(current);
    }
  }

  final FinancialAlertsCoordinator _coordinator;
  final ProfileScopeController _scope;
  late final StreamSubscription<ProfileScopeSnapshot> _scopeSub;
  late final StreamSubscription<ProfileAlertEvent> _liveSub;
  late final StreamSubscription<ProfileId> _inboxSub;
  ProfileId? _activeProfileId;
  int _refreshEpoch = 0;

  void _onScopeChanged(ProfileScopeSnapshot snap) {
    final nextId = snap.profileId;
    if (nextId == _activeProfileId) return;
    _activeProfileId = nextId;
    _refreshEpoch++;
    emit(state.copyWith(unreadCount: 0, clearBanner: true));
    if (nextId != null) {
      _refreshUnread(nextId);
    }
  }

  void _onInboxChanged(ProfileId changedProfileId) {
    if (_activeProfileId == changedProfileId) {
      _refreshUnread(changedProfileId);
    }
  }

  Future<void> _refreshUnread(ProfileId profileId) async {
    final epoch = ++_refreshEpoch;
    try {
      final count = await _coordinator.countUnread(profileId);
      if (!isClosed &&
          _activeProfileId == profileId &&
          _refreshEpoch == epoch) {
        emit(state.copyWith(unreadCount: count));
      }
    } catch (_) {
      // Ignore transient query cancellations during teardown.
    }
  }

  void _onLiveAlert(ProfileAlertEvent event) {
    if (isClosed) return;
    if (_activeProfileId != null && event.profileId != _activeProfileId) {
      return;
    }
    final isGoalWin = event.alert.kind == AlertKind.goalCompleted100;
    emit(
      state.copyWith(
        activeBanner: event.alert,
        bannerSeq: state.bannerSeq + 1,
        celebrationTick: isGoalWin
            ? state.celebrationTick + 1
            : state.celebrationTick,
      ),
    );
  }

  void dismissBanner() {
    if (state.activeBanner != null) {
      emit(state.copyWith(clearBanner: true));
    }
  }

  void triggerCelebration() {
    emit(state.copyWith(celebrationTick: state.celebrationTick + 1));
  }

  @override
  Future<void> close() async {
    await _scopeSub.cancel();
    await _liveSub.cancel();
    await _inboxSub.cancel();
    return super.close();
  }
}
