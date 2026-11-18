import 'package:equatable/equatable.dart';

/// An ad campaign attached to a byte.
class AdCampaignEntity extends Equatable {
  /// Campaign [id] titled [title] with ad tag [url].
  const AdCampaignEntity({
    required this.id,
    required this.title,
    required this.url,
  });

  /// Campaign id, reported with ad analytics.
  final String id;

  /// Campaign title, reported with ad analytics.
  final String title;

  /// VAST or VMAP ad tag URL.
  final String url;

  @override
  List<Object?> get props => [id, title, url];
}
