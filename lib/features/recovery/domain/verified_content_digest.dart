class VerifiedContentDigest {
  VerifiedContentDigest({required this.algorithm, required this.value})
    : assert(algorithm.trim().isNotEmpty),
      assert(value.trim().isNotEmpty);

  final String algorithm;
  final String value;

  String get identityKey =>
      '${algorithm.trim().toLowerCase()}:${value.trim().toLowerCase()}';
}
