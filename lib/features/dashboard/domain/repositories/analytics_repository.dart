import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/dashboard_summary.dart';

abstract interface class AnalyticsRepository {
  Future<Result<DashboardSummary>> computeDashboardSummary(
    ProfileId profileId, {
    required DashboardPeriodPreset period,
  });
}
