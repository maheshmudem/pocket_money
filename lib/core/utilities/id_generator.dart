import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Strongly-typed profile scope identifier required by every profile-owned
/// repository and use case (`ADR-008`, `AC-PROFILE-001`).
final class ProfileId extends Equatable {
  const ProfileId(this.value)
    : assert(value != '', 'ProfileId cannot be empty');

  final String value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'ProfileId($value)';
}

abstract interface class IdGenerator {
  String nextUuid();
}

final class UuidV4Generator implements IdGenerator {
  const UuidV4Generator([this._uuid = const Uuid()]);

  final Uuid _uuid;

  @override
  String nextUuid() => _uuid.v4();
}
