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
