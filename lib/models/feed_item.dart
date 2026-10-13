import 'package:flutter/cupertino.dart';

enum FeedItemType { story, video }

class FeedItem {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? mediaUrl;
  final String? partnerId;
  final String? description;
  final String status;
  final Color statusColor;
  final FeedItemType type;
  final bool isCertified;

  FeedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.thumbnailUrl,
    this.mediaUrl,
    this.partnerId,
    this.description,
    required this.status,
    required this.statusColor,
    required this.type,
    this.isCertified = false,
  });

  factory FeedItem.fromMap(String id, Map<String, dynamic> data) {
    return FeedItem(
      id: id,
      title: data['title'] ?? '',
      subtitle: data['subtitle'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      mediaUrl: data['mediaUrl'],
      partnerId: data['partnerId'],
      description: data['description'],
      status: data['status'] ?? '',
      statusColor: Color(int.parse(data['statusColor'] ?? '0xFF000000')),
      type: data['type'] == 'story' ? FeedItemType.story : FeedItemType.video,
      isCertified: data['isCertified'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'mediaUrl': mediaUrl,
      'partnerId': partnerId,
      'description': description,
      'status': status,
      'statusColor': '0x${statusColor.toARGB32().toRadixString(16).toUpperCase()}',
      'type': type == FeedItemType.story ? 'story' : 'video',
      'isCertified': isCertified,
    };
  }
}
