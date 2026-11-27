import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/bucket_list_item_entity.dart';

/// Pure-Dart repository contract for profile-isolated Bucket List items.
abstract interface class BucketListRepository {
  Future<Result<List<BucketListItemEntity>>> listItems(ProfileId profileId);

  Future<Result<BucketListItemEntity>> createItem({
    required ProfileId profileId,
    required String name,
    required int estimatedAmountMinor,
    required String currencyCode,
    required BucketPriority priority,
    required String targetYearMonth,
    int savedAmountMinor = 0,
    String? dueDateUtc,
    String? reminderAtUtc,
    String? categoryId,
    String? note,
  });

  Future<Result<BucketListItemEntity>> updateItem(BucketListItemEntity item);

  Future<Result<void>> deleteItem(ProfileId profileId, String id);

  Future<Result<BucketListItemEntity>> addSavedAmount(
    ProfileId profileId,
    String id,
    int deltaMinor,
  );
}
