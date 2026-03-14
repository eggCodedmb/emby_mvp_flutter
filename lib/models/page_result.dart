class PageResult<T> {
  const PageResult({required this.records, required this.total, required this.current});

  final List<T> records;
  final int total;
  final int current;
}
