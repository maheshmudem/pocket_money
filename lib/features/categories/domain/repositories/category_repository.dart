import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/category_entity.dart';

abstract interface class CategoryRepository {
  Stream<List<CategoryEntity>> watchCategories(
    ProfileId profileId, {
    CategoryType? type,
    bool includeInactive = false,
  });

  Future<Result<List<CategoryEntity>>> listCategories(
    ProfileId profileId, {
    CategoryType? type,
    bool includeInactive = false,
  });

  Future<Result<CategoryEntity>> createCategory({
    required ProfileId profileId,
    required String name,
    required CategoryType categoryType,
    String? parentCategoryId,
    String iconKey = 'category',
    String colorToken = 'primary',
    bool queueSync = false,
  });

  Future<Result<CategoryEntity>> updateCategory({
    required ProfileId profileId,
    required String categoryId,
    required String name,
    String? iconKey,
    bool? isActive,
  });
}
