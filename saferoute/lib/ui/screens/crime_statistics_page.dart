import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/firestore_service.dart';

class CrimeStatisticsPage extends StatefulWidget {
  const CrimeStatisticsPage({Key? key}) : super(key: key);

  @override
  State<CrimeStatisticsPage> createState() => _CrimeStatisticsPageState();
}

class _CrimeStatisticsPageState extends State<CrimeStatisticsPage> {
  String? selectedCity;
  Map<String, int> crimeStats = {};
  List<Map<String, dynamic>> crimeLocations = [];
  bool isLoading = false;
  List<String> cities = [];

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    final cityList = await FirestoreService().getAllCities();
    setState(() {
      cities = cityList;
    });
  }

  Future<void> _fetchData(String city) async {
    setState(() {
      isLoading = true;
    });
    final stats = await FirestoreService().getCrimeStatsByCity(city);
    final locations = await FirestoreService().getCrimeLocationsByCity(city);
    setState(() {
      crimeStats = stats;
      crimeLocations = locations;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text('Crime Statistics'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedCity,
                  hint: const Text('Select City'),
                  isExpanded: true,
                  items: cities.map((city) {
                    return DropdownMenuItem(
                      value: city,
                      child: Text(city),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    selectedCity = value;
                    await _fetchData(value!);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (crimeStats.isNotEmpty)
              Expanded(
                child: ListView(
                  children: [
                    _buildCard(
                      title: "Crime Distribution (Pie Chart)",
                      height: 200,
                      child: _buildPieChart(),
                    ),
                    const SizedBox(height: 16),
                    _buildCard(
                      title: "Crime Trends (Bar Chart)",
                      height: 200,
                      child: _buildBarChart(),
                    ),
                    const SizedBox(height: 16),
                    _buildCard(
                      title: "Crime Density (Heatmap)",
                      height: 300,
                      child: _buildHeatmap(),
                    ),
                  ],
                ),
              )
            else if (selectedCity != null)
              const Expanded(
                child: Center(
                  child: Text(
                    "No data available for selected city.",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
      {required String title, required double height, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(height: height, child: child),
        ],
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
            radius: 60,
            titleStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        barGroups: crimeStats.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final count = entry.value.value;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            showingTooltipIndicators: [0],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final keys = crimeStats.keys.toList();

                if (index < 0 || index >= keys.length)
                  return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    keys[index],
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value == value.floorToDouble()) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true),
      ),
    );
  }

  Widget _buildHeatmap() {
    final cityCoordinates = {
      'Lahore': LatLng(31.5204, 74.3587),
      'Islamabad': LatLng(33.6844, 73.0479),
      'Karachi': LatLng(24.8607, 67.0011),
    };

    final center = cityCoordinates[selectedCity] ?? LatLng(31.5204, 74.3587);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 11,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ),
        CircleLayer(
          circles: crimeLocations.map((location) {
            return CircleMarker(
              point: LatLng(location['lat'], location['lng']),
              radius: 10,
              color: Colors.red.withOpacity(0.5),
              useRadiusInMeter: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}
