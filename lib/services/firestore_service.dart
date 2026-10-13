import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/user_profile.dart';
import '../models/lot.dart';
import '../models/feed_item.dart';
import '../models/delivery_step.dart';

/// Firestore service for the client app.
/// Reads from the same shared 'users' and 'animals' collections.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Reads a document, retrying with backoff on transient Firestore errors
  /// (e.g. `unavailable` right after sign-in) instead of letting them crash
  /// whatever's awaiting this on the first hiccup.
  Future<DocumentSnapshot<Map<String, dynamic>>> _getWithRetry(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    const delays = [Duration(milliseconds: 400), Duration(seconds: 1)];
    for (final delay in delays) {
      try {
        return await ref.get();
      } on FirebaseException {
        await Future.delayed(delay);
      }
    }
    return ref.get();
  }

  /// Creates or overwrites a user profile document.
  Future<void> createUserProfile(UserProfile profile) async {
    await _db.collection('clients').doc(profile.uid).set(profile.toMap());
  }

  /// Ensures a profile exists for the given UID.
  /// If it doesn't exist, creates a stub profile.
  Future<void> ensureProfileExists(String uid, String? phoneNumber) async {
    final doc = await _getWithRetry(_db.collection('clients').doc(uid));
    if (!doc.exists) {
      final newProfile = UserProfile(
        uid: uid,
        phone: phoneNumber ?? '',
        role: 'client',
        displayName: 'Пользователь',
        status: 'active',
        createdAt: DateTime.now(),
      );
      await createUserProfile(newProfile);
    }
  }

  /// Fetches a user profile by UID.
  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _db.collection('clients').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserProfile.fromMap(doc.data()!);
  }

  /// Updates specific fields of a user profile.
  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('clients').doc(uid).update(data);
  }

  /// Uploads an image to Firebase Storage and returns the download URL.
  Future<String> uploadImage(String path, File file) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Stream of user profile changes (real-time).
  Stream<UserProfile?> userProfileStream(String uid) {
    return _db.collection('clients').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserProfile.fromMap(doc.data()!);
    });
  }

  /// Stream of all available lots.
  Stream<List<Lot>> getLotsStream() {
    return _db.collection('lots').snapshots().map((snap) =>
        snap.docs.map((doc) => Lot.fromMap(doc.id, doc.data())).toList());
  }

  // Buying used to happen here: the app wrote lots.bookedShares itself and kept its own
  // purchase record. The rules refuse that now, and rightly - shares are money, and only
  // createOrder may move them, in the transaction that also writes the order and prices it.
  // See EtApi.createOrder (package et_data) and screens/order_sheet.dart.

  /// Stream of lots the user has purchased shares in.
  Stream<List<Map<String, dynamic>>> getPurchasedLotsStream(String uid) {
    return _db
        .collection('clients')
        .doc(uid)
        .collection('purchases')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList());
  }

  /// Stream of story items for the feed.
  Stream<List<FeedItem>> getStories() {
    return _db
        .collection('feeds')
        .where('type', isEqualTo: 'story')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FeedItem.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Stream of video feed items.
  Stream<List<FeedItem>> getVideoFeeds() {
    return _db
        .collection('feeds')
        .where('type', isEqualTo: 'video')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FeedItem.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ─── Traceability ──────────────────────────────────────────

  /// Stream of delivery steps for a specific lot.
  Stream<List<DeliveryStep>> getDeliverySteps(String lotId) {
    return _db
        .collection('lots')
        .doc(lotId)
        .collection('deliveries')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => DeliveryStep.fromMap(doc.id, doc.data()))
            .toList());
  }
}

