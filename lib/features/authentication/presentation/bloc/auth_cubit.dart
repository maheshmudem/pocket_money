import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../data/repositories/auth_repository.dart';

enum AuthStatus { initializing, unauthenticated, authenticated, initFailure }

final class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.initializing,
    this.user,
    this.isSubmitting = false,
    this.failure,
    this.infoMessage,
  });

  final AuthStatus status;
  final AuthenticatedUser? user;
  final bool isSubmitting;
  final AppFailure? failure;
  final String? infoMessage;

  AuthState copyWith({
    AuthStatus? status,
    AuthenticatedUser? user,
    bool clearUser = false,
    bool? isSubmitting,
    AppFailure? failure,
    bool clearFailure = false,
    String? infoMessage,
    bool clearInfo = false,
  }) => AuthState(
    status: status ?? this.status,
    user: clearUser ? null : (user ?? this.user),
    isSubmitting: isSubmitting ?? this.isSubmitting,
    failure: clearFailure ? null : (failure ?? this.failure),
    infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
  );

  @override
  List<Object?> get props => [status, user, isSubmitting, failure, infoMessage];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repo) : super(const AuthState());

  final AuthRepository _repo;

  Future<void> initialize() async {
    emit(const AuthState(status: AuthStatus.initializing));
    try {
      final user = await _repo.restoreSession();
      if (user != null) {
        emit(AuthState(status: AuthStatus.authenticated, user: user));
      } else {
        emit(const AuthState(status: AuthStatus.unauthenticated));
      }
    } catch (_) {
      emit(
        const AuthState(
          status: AuthStatus.initFailure,
          failure: DatabaseFailure(
            message:
                'Unable to open secure local storage on startup. Tap retry to initialize again.',
          ),
        ),
      );
    }
  }

  Future<void> continueOfflineLocal() async {
    emit(state.copyWith(isSubmitting: true, clearFailure: true));
    final user = await _repo.startLocalWorkspace();
    emit(AuthState(status: AuthStatus.authenticated, user: user));
  }

  Future<bool> login({required String email, required String password}) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final res = await _repo.login(email: email, password: password);
    return res.fold(
      onSuccess: (user) {
        emit(AuthState(status: AuthStatus.authenticated, user: user));
        return true;
      },
      onFailure: (f) {
        emit(state.copyWith(isSubmitting: false, failure: f));
        return false;
      },
    );
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final res = await _repo.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    return res.fold(
      onSuccess: (user) {
        emit(AuthState(status: AuthStatus.authenticated, user: user));
        return true;
      },
      onFailure: (f) {
        emit(state.copyWith(isSubmitting: false, failure: f));
        return false;
      },
    );
  }

  Future<void> requestPasswordReset(String email) async {
    emit(
      state.copyWith(isSubmitting: true, clearFailure: true, clearInfo: true),
    );
    final res = await _repo.requestPasswordReset(email);
    res.fold(
      onSuccess: (_) => emit(
        state.copyWith(
          isSubmitting: false,
          infoMessage:
              'If an account exists for that email, recovery instructions have been sent.',
        ),
      ),
      onFailure: (f) => emit(state.copyWith(isSubmitting: false, failure: f)),
    );
  }

  Future<void> logout() async {
    await _repo.logout();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
