import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utilities/clock.dart';
import '../../data/app_lock_service.dart';

final class AppLockState extends Equatable {
  const AppLockState({
    this.isEnabled = false,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
    this.isLocked = false,
    this.timeoutSeconds = 30,
    this.errorMessage,
    this.failedAttempts = 0,
    this.lockoutUntilUtc,
  });

  final bool isEnabled;
  final bool biometricEnabled;
  final bool biometricAvailable;
  final bool isLocked;
  final int timeoutSeconds;
  final String? errorMessage;
  final int failedAttempts;
  final DateTime? lockoutUntilUtc;

  bool isLockedOutAt(DateTime nowUtc) =>
      lockoutUntilUtc != null && nowUtc.isBefore(lockoutUntilUtc!);

  int remainingLockoutSeconds(DateTime nowUtc) {
    if (lockoutUntilUtc == null) return 0;
    final diff = lockoutUntilUtc!.difference(nowUtc).inSeconds;
    return diff > 0 ? diff : 0;
  }

  AppLockState copyWith({
    bool? isEnabled,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool? isLocked,
    int? timeoutSeconds,
    String? errorMessage,
    bool clearError = false,
    int? failedAttempts,
    DateTime? lockoutUntilUtc,
    bool clearLockout = false,
  }) => AppLockState(
    isEnabled: isEnabled ?? this.isEnabled,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    isLocked: isLocked ?? this.isLocked,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    failedAttempts: failedAttempts ?? this.failedAttempts,
    lockoutUntilUtc: clearLockout
        ? null
        : (lockoutUntilUtc ?? this.lockoutUntilUtc),
  );

  @override
  List<Object?> get props => [
    isEnabled,
    biometricEnabled,
    biometricAvailable,
    isLocked,
    timeoutSeconds,
    errorMessage,
    failedAttempts,
    lockoutUntilUtc,
  ];
}

class AppLockCubit extends Cubit<AppLockState> {
  AppLockCubit({required AppLockService service, required UtcClock clock})
    : _service = service,
      _clock = clock,
      super(const AppLockState());

  final AppLockService _service;
  final UtcClock _clock;
  DateTime? _backgroundedAtUtc;

  Future<void> initialize() async {
    try {
      final enabled = await _service.isAppLockEnabled();
      final bioEnabled = await _service.isBiometricEnabled();
      final bioAvail = await _service.canUseBiometrics();
      final timeout = await _service.getLockTimeoutSeconds();
      emit(
        AppLockState(
          isEnabled: enabled,
          biometricEnabled: bioEnabled,
          biometricAvailable: bioAvail,
          isLocked: enabled,
          timeoutSeconds: timeout,
        ),
      );
    } catch (_) {
      // Keep safe unlocked default on first-run storage error; AuthCubit surfaces init failure.
    }
  }

  void onAppBackgrounded() {
    if (!state.isEnabled) return;
    _backgroundedAtUtc = _clock.nowUtc();
    if (state.timeoutSeconds == 0) {
      emit(state.copyWith(isLocked: true, clearError: true));
    }
  }

  void onAppResumed() {
    if (!state.isEnabled || _backgroundedAtUtc == null) return;
    final elapsed = _clock.nowUtc().difference(_backgroundedAtUtc!).inSeconds;
    _backgroundedAtUtc = null;
    if (elapsed >= state.timeoutSeconds) {
      emit(state.copyWith(isLocked: true, clearError: true));
    }
  }

  void lockNow() {
    if (state.isEnabled) {
      emit(state.copyWith(isLocked: true, clearError: true));
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometricEnabled) return false;
    final ok = await _service.authenticateWithBiometrics();
    if (ok) {
      emit(
        state.copyWith(
          isLocked: false,
          clearError: true,
          failedAttempts: 0,
          clearLockout: true,
        ),
      );
      return true;
    }
    // AC-SEC-001: keep data hidden and guide user to fallback PIN.
    emit(
      state.copyWith(
        isLocked: true,
        errorMessage:
            'Biometric verification unavailable or cancelled. Enter your fallback PIN to unlock.',
      ),
    );
    return false;
  }

  Future<bool> unlockWithPin(String pin) async {
    final now = _clock.nowUtc();
    if (state.isLockedOutAt(now)) {
      final remaining = state.remainingLockoutSeconds(now);
      emit(
        state.copyWith(
          isLocked: true,
          errorMessage: 'Too many attempts. Try again in ${remaining}s.',
        ),
      );
      return false;
    }

    final ok = await _service.verifyPin(pin);
    if (ok) {
      emit(
        state.copyWith(
          isLocked: false,
          clearError: true,
          failedAttempts: 0,
          clearLockout: true,
        ),
      );
      return true;
    }
    final nextAttempts = state.failedAttempts + 1;
    DateTime? nextLockout;
    String msg = 'Incorrect PIN. Please try again.';
    if (nextAttempts >= 5) {
      final backoffMultiplier = math.pow(2, math.min(nextAttempts - 5, 4));
      final cooldownSeconds = (30 * backoffMultiplier).toInt();
      nextLockout = now.add(Duration(seconds: cooldownSeconds));
      msg = 'Too many failed attempts. Locked for ${cooldownSeconds}s.';
    }
    emit(
      state.copyWith(
        isLocked: true,
        failedAttempts: nextAttempts,
        lockoutUntilUtc: nextLockout,
        errorMessage: msg,
      ),
    );
    return false;
  }

  /// Verifies the current PIN for sensitive Settings changes (disable / change PIN).
  Future<bool> verifyCurrentPin(String pin) => _service.verifyPin(pin);

  /// Updates the fallback PIN after verifying the existing PIN.
  Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final valid = await _service.verifyPin(currentPin);
    if (!valid) return false;
    await configureLock(
      fallbackPin: newPin,
      useBiometrics: state.biometricEnabled,
      timeoutSeconds: state.timeoutSeconds,
    );
    return true;
  }

  Future<void> configureLock({
    required String fallbackPin,
    required bool useBiometrics,
    int timeoutSeconds = 30,
  }) async {
    await _service.enableAppLock(
      fallbackPin: fallbackPin,
      useBiometrics: useBiometrics,
      timeoutSeconds: timeoutSeconds,
    );
    final bioAvail = await _service.canUseBiometrics();
    emit(
      state.copyWith(
        isEnabled: true,
        biometricEnabled: useBiometrics && bioAvail,
        biometricAvailable: bioAvail,
        isLocked: false,
        timeoutSeconds: timeoutSeconds,
        failedAttempts: 0,
        clearLockout: true,
        clearError: true,
      ),
    );
  }

  Future<void> disableLock() async {
    await _service.disableAppLock();
    emit(
      state.copyWith(
        isEnabled: false,
        biometricEnabled: false,
        isLocked: false,
        failedAttempts: 0,
        clearLockout: true,
        clearError: true,
      ),
    );
  }
}
