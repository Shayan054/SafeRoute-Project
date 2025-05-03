// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, int>> getCrimeStatsByCity(String city) async {
    try {
      final snapshot = await _firestore
          .collection('firestore_crime')
          .where('city', isEqualTo: city)
          .get();

      Map<String, int> crimeCounts = {};
      
      for (var doc in snapshot.docs) {
        String crimeType = doc['crime_type'];
        crimeCounts[crimeType] = (crimeCounts[crimeType] ?? 0) + 1;
      }

      return crimeCounts;
    } catch (e) {
      print('Error getting crime stats: $e');
      return {};
    }
  }
}
