import 'package:cloud_firestore/cloud_firestore.dart';

class Animal {
  final String id;
  final String partnerId;
  final String breed;
  final String subBreed;
  final String status; // 'active', 'pending_inspection', 'sold'
  final double weight;
  final String ageCategory;
  final String? imageUrl;
  final double price;
  final String region;
  final DateTime createdAt;

  Animal({
    required this.id,
    required this.partnerId,
    required this.breed,
    required this.subBreed,
    this.status = 'active',
    required this.weight,
    required this.ageCategory,
    this.imageUrl,
    this.price = 0.0,
    this.region = 'Unknown',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayId {
    final prefix = breed.length >= 2 ? breed.substring(0, 2).toUpperCase() : 'AN';
    final suffix = id.hashCode.abs() % 10000;
    return '#$prefix-$suffix';
  }

  String get statusLabel {
    switch (status) {
      case 'active': return 'В НАЛИЧИИ';
      case 'pending_inspection': return 'ОЖИДАЕТСЯ';
      case 'sold': return 'ПРОДАН';
      default: return status.toUpperCase();
    }
  }

  factory Animal.fromMap(String id, Map<String, dynamic> map) {
    return Animal(
      id: id,
      partnerId: map['partnerId'] ?? '',
      breed: map['breed'] ?? '',
      subBreed: map['subBreed'] ?? '',
      status: map['status'] ?? 'active',
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
      ageCategory: map['ageCategory'] ?? '',
      imageUrl: map['imageUrl'],
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      region: map['region'] ?? 'Unknown',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
