class UploadResult {
  final String filename;
  final String? movedTo;

  UploadResult({required this.filename, this.movedTo});

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(filename: json['filename'], movedTo: json['moved_to']);
  }

  @override
  String toString() => '$filename → ${movedTo ?? "No folder"}';
}
