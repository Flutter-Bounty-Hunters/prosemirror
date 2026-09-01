/// Transposes a 2D array by flipping columns to rows.
///
/// Transposition is a familiar algebra concept where the matrix is flipped
/// along its diagonal.
List<List<T>> transpose<T>(List<List<T>> array) {
  return List<List<T>>.generate(array[0].length, (i) => List<T>.generate(array.length, (j) => array[j][i]));
}
