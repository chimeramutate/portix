import 'package:portix/src/core/error/failure.dart';
import 'package:portix/src/core/usecase/either.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

abstract class SshProfileRepository {
  Future<Either<Failure, List<SshProfile>>> getProfiles();
  Future<Either<Failure, SshProfile>> saveProfile(SshProfile profile);
  Future<Either<Failure, SshProfile>> testConnection(SshProfile profile);
  Future<Either<Failure, SshProfile>> connect(SshProfile profile);
  Future<Either<Failure, Unit>> deleteProfile(String id);
}

class Unit {
  const Unit();
}
