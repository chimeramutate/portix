import '../error/failure.dart';
import '../usecase/either.dart';
export '../usecase/either.dart';

typedef Result<T> = Either<Failure, T>;

class AppFailure extends Failure {
  const AppFailure(super.message, {this.cause});

  final Object? cause;

  @override
  List<Object?> get props => [message, cause];
}
