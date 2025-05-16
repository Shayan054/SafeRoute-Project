// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<String>> getAllCities() async{
    final snapshot=await _firestore.collection('firestore_crime').get();
    final cities =snapshot.docs
    .map((doc)=>doc['city'].toString())
    .toSet()
    .toList();
    return cities;
  }

  Future<List<Map<String,dynamic>>> getCrimeLocationsByCity(String city) async{
    final QuerySnapshot = await FirebaseFirestore.instance
    .collection('firestore_crime')
    .where('city',isEqualTo: city).get();
    return QuerySnapshot.docs.map((doc){
      final data=doc.data();
      return{
        'lat':data['latitude'],
        'lng':data['longitude'],
      };
    }).toList();
  }

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

  Future<List<Map<String, dynamic>>> getAllCrimeLocations() async {
    final snapshot = await _firestore.collection('firestore_crime').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'lat': data['latitude'],
        'lng': data['longitude'],
        'crime_type': data['crime_type'],
        'city': data['city'],
      };
    }).toList();
  }
}
