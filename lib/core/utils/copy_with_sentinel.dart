/// Sentinel value used by `copyWith` methods to distinguish
/// "argument not provided" from an explicit `null`.
class CopyWithSentinel {
  const CopyWithSentinel();
}

/// Default sentinel instance for `copyWith` optional nullable parameters.
///
/// Pass `null` explicitly to clear a nullable field; omit the argument to
/// keep its current value.
const Object kCopyWithUnset = CopyWithSentinel();
