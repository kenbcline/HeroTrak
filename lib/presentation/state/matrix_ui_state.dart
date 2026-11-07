import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Column identifier of the selected matrix column:
/// `'1'`–`'12'` for segments, `'post12'` for the Post-12 column, or `null`
/// when no column is selected.
///
/// Currently only the Post-12 end-of-Turn column is selectable by clicking
/// it (header or body cell).
final selectedColumnProvider = StateProvider<String?>((ref) => null);