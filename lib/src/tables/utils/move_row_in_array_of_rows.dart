/// Move a row in an array of rows.
List<T> moveRowInArrayOfRows<T>(List<T> rows, List<int> indexesOrigin, List<int> indexesTarget, int directionOverride) {
  final direction = indexesOrigin[0] > indexesTarget[0] ? -1 : 1;

  final rowsExtracted = rows.sublist(indexesOrigin[0], indexesOrigin[0] + indexesOrigin.length);
  rows.removeRange(indexesOrigin[0], indexesOrigin[0] + indexesOrigin.length);
  final positionOffset = rowsExtracted.length % 2 == 0 ? 1 : 0;
  int target;

  if (directionOverride == -1 && direction == 1) {
    target = indexesTarget[0] - 1;
  } else if (directionOverride == 1 && direction == -1) {
    target = indexesTarget[indexesTarget.length - 1] - positionOffset + 1;
  } else {
    target = direction == -1 ? indexesTarget[0] : indexesTarget[indexesTarget.length - 1] - positionOffset;
  }

  // JavaScript's `splice` clamps the insertion index to the array's length,
  // whereas Dart's `insertAll` throws for out-of-range indices, so clamp here.
  final clampedTarget = target < 0 ? 0 : (target > rows.length ? rows.length : target);
  rows.insertAll(clampedTarget, rowsExtracted);
  return rows;
}
