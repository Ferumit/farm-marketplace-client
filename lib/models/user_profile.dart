import 'package:cloud_firestore/cloud_firestore.dart';

/// Профиль покупателя: clients/{uid}.
///
/// Здесь только то, что приложение действительно спрашивает и показывает. Поля старой модели —
/// ИИН, счёт, документ, кошелёк, достижения — убраны: ни один экран их не заполнял, но toMap()
/// писал их null'ами в каждый профиль. Поле с именем `iin` или `iban` в документе покупателя
/// выглядит как сбор паспортных и банковских данных — и в анкете Data safety его пришлось бы
/// объявлять как сбор, которого нет. ИИН на платформе есть только у хозяйств, и лежит он в
/// приватной записи partners/{uid}/private/identity.
class UserProfile {
  final String uid;
  final String phone;
  final String role; // 'client'
  final String? displayName;
  final String status; // 'pending_review', 'verified', 'active'
  final DateTime createdAt;

  // ─── Extended fields ─────────────────────────────────────────
  final String? avatarUrl;
  final String? city;
  final double rating;
  final int totalDeals;

  UserProfile({
    required this.uid,
    required this.phone,
    required this.role,
    this.displayName,
    this.status = 'pending_review',
    DateTime? createdAt,
    this.avatarUrl,
    this.city,
    this.rating = 0.0,
    this.totalDeals = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  String get shortName => displayName ?? phone;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phone': phone,
      'role': role,
      'displayName': displayName,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'avatarUrl': avatarUrl,
      'city': city,
      'rating': rating,
      'totalDeals': totalDeals,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'client',
      displayName: map['displayName'],
      status: map['status'] ?? 'pending_review',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      avatarUrl: map['avatarUrl'],
      city: map['city'],
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      totalDeals: (map['totalDeals'] as num?)?.toInt() ?? 0,
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? status,
    String? avatarUrl,
    String? city,
    double? rating,
    int? totalDeals,
  }) {
    return UserProfile(
      uid: uid,
      phone: phone,
      role: role,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      createdAt: createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      city: city ?? this.city,
      rating: rating ?? this.rating,
      totalDeals: totalDeals ?? this.totalDeals,
    );
  }
}
