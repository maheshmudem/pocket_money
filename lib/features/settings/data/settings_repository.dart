import '../../../core/database/app_database.dart';
import '../../../core/utilities/clock.dart';

final class SettingsRepository {
  SettingsRepository({required AppDatabase db, required UtcClock clock})
    : _db = db,
      _clock = clock;

  final AppDatabase _db;
  final UtcClock _clock;

  Future<String?> getString(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.settingKey.equals(key))).getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> setString(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            settingKey: key,
            settingValue: value,
            updatedAtUtc: _clock.nowIsoUtc(),
          ),
        );
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final raw = await getString(key);
    if (raw == null) return defaultValue;
    return raw == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? 'true' : 'false');

  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final raw = await getString(key);
    return int.tryParse(raw ?? '') ?? defaultValue;
  }

  Future<void> setInt(String key, int value) =>
      setString(key, value.toString());
}
