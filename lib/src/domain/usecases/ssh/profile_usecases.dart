import 'package:portix/src/core/error/failure.dart';
import 'package:portix/src/core/usecase/either.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/domain/repositories/ssh/index.dart';

class GetProfiles {
  const GetProfiles(this.repository);
  final SshProfileRepository repository;

  Future<Either<Failure, List<SshProfile>>> call() => repository.getProfiles();
}

class SaveProfile {
  const SaveProfile(this.repository);
  final SshProfileRepository repository;

  Future<Either<Failure, SshProfile>> call(SshProfile profile) {
    return repository.saveProfile(profile);
  }
}

class TestConnection {
  const TestConnection(this.repository);
  final SshProfileRepository repository;

  Future<Either<Failure, SshProfile>> call(SshProfile profile) {
    return repository.testConnection(profile);
  }
}

class ConnectProfile {
  const ConnectProfile(this.repository);
  final SshProfileRepository repository;

  Future<Either<Failure, SshProfile>> call(SshProfile profile) {
    return repository.connect(profile);
  }
}

class DeleteProfile {
  const DeleteProfile(this.repository);
  final SshProfileRepository repository;

  Future<Either<Failure, Unit>> call(String id) {
    return repository.deleteProfile(id);
  }
}

class ReadPasswordForEdit {
  const ReadPasswordForEdit(this.repository);
  final SshProfileRepository repository;

  /// Returns the real stored password, or null if none was found.
  Future<String?> call(String profileId) {
    return repository.readPasswordForEdit(profileId);
  }
}
