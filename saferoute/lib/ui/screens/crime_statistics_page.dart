// lib/screens/crime_statistics_page.dart
import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import 'package:fl_chart/fl_chart.dart';

class CrimeStatisticsPage extends StatefulWidget {
  const CrimeStatisticsPage({Key? key}) : super(key: key);

  @override
  State<CrimeStatisticsPage> createState() => _CrimeStatisticsPageState();
}

class _CrimeStatisticsPageState extends State<CrimeStatisticsPage> {
  String? selectedCity;
  Map<String, int> crimeStats = {};
  bool isLoading = false;

  final List<String> cities = ['Lahore', 'Karachi', 'Islamabad'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crime Statistics')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<String>(
              value: selectedCity,
              hint: const Text('Select City'),
              items: cities.map((city) {
                return DropdownMenuItem(
                  value: city,
                  child: Text(city),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  selectedCity = value;
                  isLoading = true;
                });
                final stats = await FirestoreService().getCrimeStatsByCity(value!);
                setState(() {
                  crimeStats = stats;
                  isLoading = false;
                });
              },
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const CircularProgressIndicator()
            else if (crimeStats.isNotEmpty)
              Expanded(child: _buildPieChart())
            else if (selectedCity != null)
              const Text("No data available for selected city."),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    final total = crimeStats.values.fold(0, (sum, val) => sum + val);
    final colors = [Colors.red, Colors.blue, Colors.green, Colors.orange];

    return PieChart(
      PieChartData(
        sections: crimeStats.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final type = entry.value.key;
          final count = entry.value.value;
          final percentage = ((count / total) * 100).toStringAsFixed(1);

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: count.toDouble(),
            title: "$type\n$percentage%",
            radius: 100,
            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          );
        }).toList(),
      ),
    );
  }
}