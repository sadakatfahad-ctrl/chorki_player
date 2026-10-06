import 'package:equatable/equatable.dart';

class ByteDataEntity extends Equatable {
  const ByteDataEntity({
    required this.id,
    required this.thumbnailUrl,
    required this.url,
  });

  final int id;
  final String thumbnailUrl;
  final String url;

  @override
  List<Object?> get props => [id, thumbnailUrl, url];
}
