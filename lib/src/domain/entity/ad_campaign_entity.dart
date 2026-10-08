import 'package:equatable/equatable.dart';

class AdCampaignEntity extends Equatable {
  const AdCampaignEntity({
    required this.id,
    required this.title,
    required this.url,
  });

  final String id;
  final String title;
  final String url;

  @override
  List<Object?> get props => [id, title, url];
}
