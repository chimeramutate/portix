import '../error/failure.dart';
export '../error/failure.dart';

sealed class Either<L, R> {
  const Either();

  T fold<T>(T Function(L value) left, T Function(R value) right) {
    return switch (this) {
      Left<L, R>(value: final value) => left(value),
      Right<L, R>(value: final value) => right(value),
    };
  }

  bool get isRight => this is Right<L, R>;
  bool get isLeft => this is Left<L, R>;
}

class Left<L, R> extends Either<L, R> {
  const Left(this.value);
  final L value;
}

class Right<L, R> extends Either<L, R> {
  const Right(this.value);
  final R value;
}

typedef Result<T> = Either<Failure, T>;

class AppFailure extends Failure {
  const AppFailure(super.message, {this.cause});

  final Object? cause;

  @override
  List<Object?> get props => [message, cause];

  @override
  String toString() {
    if (cause != null) {
      return '$message: $cause';
    }
    return message;
  }
}
