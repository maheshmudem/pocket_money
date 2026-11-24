import 'package:equatable/equatable.dart';

import '../../../../core/utilities/id_generator.dart';

enum CategoryType {
  income('income', 'Income'),
  expense('expense', 'Expense'),
  transfer('transfer', 'Transfer'),
  other('other', 'Other');

  const CategoryType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CategoryType fromWire(String raw) => switch (raw) {
    'income' => CategoryType.income,
    'expense' => CategoryType.expense,
    'transfer' => CategoryType.transfer,
    _ => CategoryType.other,
  };
}

final class CategoryEntity extends Equatable {
  const CategoryEntity({
    required this.id,
    required this.profileId,
    required this.ledgerAccountId,
    required this.name,
    required this.categoryType,
    required this.iconKey,
    required this.colorToken,
    required this.isSystem,
    required this.isActive,
    this.parentCategoryId,
  });

  final String id;
  final ProfileId profileId;
  final String ledgerAccountId;
  final String name;
  final CategoryType categoryType;
  final String? parentCategoryId;
  final String iconKey;
  final String colorToken;
  final bool isSystem;
  final bool isActive;

  @override
  List<Object?> get props => [
    id,
    profileId,
    ledgerAccountId,
    name,
    categoryType,
    parentCategoryId,
    iconKey,
    colorToken,
    isSystem,
    isActive,
  ];
}
