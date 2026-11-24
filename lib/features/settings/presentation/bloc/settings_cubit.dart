import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/privacy_screen_service.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../data/settings_repository.dart';

final class SettingsState extends Equatable {
  const SettingsState({
    this.isLoaded = false,
    this.hasCompletedOnboarding = false,
    this.themeMode = ThemeMode.system,
    this.hideBalances = false,
    this.privacyCurtainEnabled = true,
    this.blockScreenshotsEnabled = true,
    this.notificationsEnabled = true,
    this.budgetAlertsEnabled = true,
    this.lowBalanceAlertsEnabled = true,
    this.lowBalanceThresholdMinor = 100000,
    this.goalMilestoneAlertsEnabled = true,
    this.dailyReminderEnabled = false,
    this.dailyReminderHour = 20,
    this.dailyReminderMinute = 30,
  });

  final bool isLoaded;
  final bool hasCompletedOnboarding;
  final ThemeMode themeMode;
  final bool hideBalances;
  final bool privacyCurtainEnabled;
  final bool blockScreenshotsEnabled;
  final bool notificationsEnabled;
  final bool budgetAlertsEnabled;
  final bool lowBalanceAlertsEnabled;
  final int lowBalanceThresholdMinor;
  final bool goalMilestoneAlertsEnabled;
  final bool dailyReminderEnabled;
  final int dailyReminderHour;
  final int dailyReminderMinute;

  SettingsState copyWith({
    bool? isLoaded,
    bool? hasCompletedOnboarding,
    ThemeMode? themeMode,
    bool? hideBalances,
    bool? privacyCurtainEnabled,
    bool? blockScreenshotsEnabled,
    bool? notificationsEnabled,
    bool? budgetAlertsEnabled,
    bool? lowBalanceAlertsEnabled,
    int? lowBalanceThresholdMinor,
    bool? goalMilestoneAlertsEnabled,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
  }) => SettingsState(
    isLoaded: isLoaded ?? this.isLoaded,
    hasCompletedOnboarding:
        hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    themeMode: themeMode ?? this.themeMode,
    hideBalances: hideBalances ?? this.hideBalances,
    privacyCurtainEnabled: privacyCurtainEnabled ?? this.privacyCurtainEnabled,
    blockScreenshotsEnabled:
        blockScreenshotsEnabled ?? this.blockScreenshotsEnabled,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    budgetAlertsEnabled: budgetAlertsEnabled ?? this.budgetAlertsEnabled,
    lowBalanceAlertsEnabled:
        lowBalanceAlertsEnabled ?? this.lowBalanceAlertsEnabled,
    lowBalanceThresholdMinor:
        lowBalanceThresholdMinor ?? this.lowBalanceThresholdMinor,
    goalMilestoneAlertsEnabled:
        goalMilestoneAlertsEnabled ?? this.goalMilestoneAlertsEnabled,
    dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
    dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
    dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
  );

  @override
  List<Object?> get props => [
    isLoaded,
    hasCompletedOnboarding,
    themeMode,
    hideBalances,
    privacyCurtainEnabled,
    blockScreenshotsEnabled,
    notificationsEnabled,
    budgetAlertsEnabled,
    lowBalanceAlertsEnabled,
    lowBalanceThresholdMinor,
    goalMilestoneAlertsEnabled,
    dailyReminderEnabled,
    dailyReminderHour,
    dailyReminderMinute,
  ];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(
    this._repo, {
    FinancialAlertsCoordinator? alertsCoordinator,
    PrivacyScreenService? privacyScreen,
  }) : _alertsCoordinator = alertsCoordinator,
       _privacyScreen = privacyScreen,
       super(const SettingsState());

  final SettingsRepository _repo;
  final FinancialAlertsCoordinator? _alertsCoordinator;
  final PrivacyScreenService? _privacyScreen;

  Future<void> load() async {
    try {
      final onboardingRaw = await _repo.getString('onboarding.completed');
      final authMode = await _repo.getString('auth.mode');
      final hasCompletedOnboarding = onboardingRaw != null
          ? onboardingRaw == 'true'
          : (authMode == 'local' || authMode == 'cloud');
      final themeRaw = await _repo.getString('ui.theme_mode');
      final hideBalances = await _repo.getBool('ui.hide_balances');
      final curtain = await _repo.getBool(
        'security.privacy_curtain_enabled',
        defaultValue: true,
      );
      final blockScreenshots = await _repo.getBool(
        'security.block_screenshots_enabled',
        defaultValue: true,
      );
      final notificationsEnabled = await _repo.getBool(
        'alerts.notifications_enabled',
        defaultValue: true,
      );
      final budgetAlertsEnabled = await _repo.getBool(
        'alerts.budget_enabled',
        defaultValue: true,
      );
      final lowBalanceAlertsEnabled = await _repo.getBool(
        'alerts.low_balance_enabled',
        defaultValue: true,
      );
      final thresholdRaw = await _repo.getString(
        'alerts.low_balance_threshold_minor',
      );
      final lowBalanceThresholdMinor =
          int.tryParse(thresholdRaw ?? '') ?? 100000;
      final goalMilestoneAlertsEnabled = await _repo.getBool(
        'alerts.goal_milestones_enabled',
        defaultValue: true,
      );
      final dailyReminderEnabled = await _repo.getBool(
        'alerts.daily_reminder_enabled',
        defaultValue: false,
      );
      final hourRaw = await _repo.getString('alerts.daily_reminder_hour');
      final minuteRaw = await _repo.getString('alerts.daily_reminder_minute');
      final dailyReminderHour = int.tryParse(hourRaw ?? '') ?? 20;
      final dailyReminderMinute = int.tryParse(minuteRaw ?? '') ?? 30;

      final mode = switch (themeRaw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      emit(
        SettingsState(
          isLoaded: true,
          hasCompletedOnboarding: hasCompletedOnboarding,
          themeMode: mode,
          hideBalances: hideBalances,
          privacyCurtainEnabled: curtain,
          blockScreenshotsEnabled: blockScreenshots,
          notificationsEnabled: notificationsEnabled,
          budgetAlertsEnabled: budgetAlertsEnabled,
          lowBalanceAlertsEnabled: lowBalanceAlertsEnabled,
          lowBalanceThresholdMinor: lowBalanceThresholdMinor,
          goalMilestoneAlertsEnabled: goalMilestoneAlertsEnabled,
          dailyReminderEnabled: dailyReminderEnabled,
          dailyReminderHour: dailyReminderHour,
          dailyReminderMinute: dailyReminderMinute,
        ),
      );
      await _privacyScreen?.setSecureScreen(enabled: blockScreenshots);
    } catch (_) {
      // Keep safe defaults if storage is initializing or retrying.
      emit(state.copyWith(isLoaded: true));
    }
  }

  Future<void> completeOnboarding() async {
    emit(state.copyWith(isLoaded: true, hasCompletedOnboarding: true));
    await _repo.setBool('onboarding.completed', true);
  }

  Future<void> resetOnboarding() async {
    emit(state.copyWith(isLoaded: true, hasCompletedOnboarding: false));
    await _repo.setBool('onboarding.completed', false);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(state.copyWith(themeMode: mode));
    await _repo.setString('ui.theme_mode', mode.name);
  }

  /// One-tap instant toggle between crisp Daylight Light and Obsidian Dark themes.
  Future<void> toggleLightDark(Brightness currentEffectiveBrightness) async {
    final next = currentEffectiveBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setThemeMode(next);
  }

  Future<void> toggleHideBalances() async {
    final next = !state.hideBalances;
    emit(state.copyWith(hideBalances: next));
    await _repo.setBool('ui.hide_balances', next);
  }

  Future<void> setPrivacyCurtain(bool enabled) async {
    emit(state.copyWith(privacyCurtainEnabled: enabled));
    await _repo.setBool('security.privacy_curtain_enabled', enabled);
  }

  /// Controls native OS screenshot, screen-recording, and screen-casting
  /// protection (`FLAG_SECURE` on Android) independently of the app-switcher
  /// privacy curtain.
  Future<void> setBlockScreenshots(bool enabled) async {
    emit(state.copyWith(blockScreenshotsEnabled: enabled));
    await _repo.setBool('security.block_screenshots_enabled', enabled);
    await _privacyScreen?.setSecureScreen(enabled: enabled);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    if (enabled) {
      await _alertsCoordinator?.requestPermission();
    }
    emit(state.copyWith(notificationsEnabled: enabled));
    await _repo.setBool('alerts.notifications_enabled', enabled);
  }

  Future<void> setBudgetAlertsEnabled(bool enabled) async {
    emit(state.copyWith(budgetAlertsEnabled: enabled));
    await _repo.setBool('alerts.budget_enabled', enabled);
  }

  Future<void> setLowBalanceAlertsEnabled(bool enabled) async {
    emit(state.copyWith(lowBalanceAlertsEnabled: enabled));
    await _repo.setBool('alerts.low_balance_enabled', enabled);
  }

  Future<void> setLowBalanceThresholdMinor(int thresholdMinor) async {
    emit(state.copyWith(lowBalanceThresholdMinor: thresholdMinor));
    await _repo.setString(
      'alerts.low_balance_threshold_minor',
      thresholdMinor.toString(),
    );
  }

  Future<void> setGoalMilestoneAlertsEnabled(bool enabled) async {
    emit(state.copyWith(goalMilestoneAlertsEnabled: enabled));
    await _repo.setBool('alerts.goal_milestones_enabled', enabled);
  }

  Future<void> setDailyReminder({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    final h = hour ?? state.dailyReminderHour;
    final m = minute ?? state.dailyReminderMinute;
    emit(
      state.copyWith(
        dailyReminderEnabled: enabled,
        dailyReminderHour: h,
        dailyReminderMinute: m,
      ),
    );
    await _repo.setBool('alerts.daily_reminder_enabled', enabled);
    await _repo.setString('alerts.daily_reminder_hour', h.toString());
    await _repo.setString('alerts.daily_reminder_minute', m.toString());
    await _alertsCoordinator?.syncDailyReminder(
      enabled: enabled,
      hour: h,
      minute: m,
    );
  }
}
