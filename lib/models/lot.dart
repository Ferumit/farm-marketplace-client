import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a group of animals assembled into a lot for sale.
class Lot {
  final String id;
  final String partnerId;
  final String name;
  final String description;
  final List<String> animalIds;
  final double totalWeight;
  final double pricePerShare;
  final String status; // 'draft', 'open', 'fully_booked', 'in_transit', 'sold'
  final int totalShares;
  final int bookedShares;
  final String location;
  final String? imageUrl;
  final String? meatType; // 'cattle'/'horse' - set by ET_partners at lot creation
  final DateTime createdAt;

  Lot({
    required this.id,
    required this.partnerId,
    required this.name,
    this.description = '',
    required this.animalIds,
    this.totalWeight = 0,
    this.pricePerShare = 0,
    this.status = 'draft',
    this.totalShares = 4,
    this.bookedShares = 0,
    this.location = 'Казахстан',
    this.imageUrl,
    this.meatType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get bookingPercent =>
      totalShares == 0 ? 0 : bookedShares / totalShares;

  bool get isFullyBooked => bookedShares >= totalShares;
  int get availableShares => totalShares - bookedShares;

  factory Lot.fromMap(String id, Map<String, dynamic> map) => Lot(
    id: id,
    partnerId: map['partnerId'] ?? '',
    name: map['name'] ?? map['title'] ?? '',
    description: map['description'] ?? '',
    animalIds: List<String>.from(map['animalIds'] ?? []),
    totalWeight: (map['totalWeight'] as num?)?.toDouble() ?? 0,
    pricePerShare: (map['pricePerShare'] as num?)?.toDouble() ?? 0,
    status: map['status'] ?? 'draft',
    totalShares: (map['totalShares'] as num?)?.toInt() ?? 4,
    bookedShares: (map['bookedShares'] as num?)?.toInt() ?? 0,
    location: map['location'] ?? 'Казахстан',
    imageUrl: map['imageUrl'] as String?,
    meatType: map['meatType'] as String?,
    createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'partnerId': partnerId,
    'name': name,
    'description': description,
    'animalIds': animalIds,
    'totalWeight': totalWeight,
    'pricePerShare': pricePerShare,
    'status': status,
    'totalShares': totalShares,
    'bookedShares': bookedShares,
    'location': location,
    'imageUrl': imageUrl,
    'meatType': meatType,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
