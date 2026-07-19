import 'package:portix/src/core/error/failure.dart';
import 'package:portix/src/core/usecase/either.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

abstract class SshProfileRepository {
  Future<Either<Failure, List<SshProfile>>> getProfiles();
  Future<Either<Failure, SshProfile>> saveProfile(SshProfile profile);
  Future<Either<Failure, SshProfile>> testConnection(SshProfile profile);
  Future<Either<Failure, SshProfile>> connect(SshProfile profile);
  Future<Either<Failure, Unit>> deleteProfile(String id);

  /// Returns the real password from secure storage for a password-auth profile.
  /// Used when opening the edit form so the field shows the actual stored
  /// password instead of the sentinel placeholder.
  Future<String?> readPasswordForEdit(String profileId);
}

class Unit {
  const Unit();
}
