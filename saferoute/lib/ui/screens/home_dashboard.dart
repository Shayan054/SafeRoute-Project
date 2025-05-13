import 'package:flutter/material.dart';
import '../widgets/dashboard_card.dart';
import '../constants/colors.dart';
import 'crime_statistics_page.dart';
import 'map_screen.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _buildBottomNavBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              const CircleAvatar(
                radius: 40,
                backgroundImage: AssetImage(
                    'assets/images/Uw.jpg'), // Replace with your asset path
              ),
              const SizedBox(height: 24),
              DashboardCard(
                title: "SafeRoute Map",
                subtitle: "Explore safe paths nearby",
                imagePath: "assets/images/map.jpg",
                buttonText: "View Map",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>  MapScreen(),
                    ),
                  );
                  // TODO: Navigate to map screen
                },
              ),
              const SizedBox(height: 16),
              DashboardCard(
                title: "Crime Stats",
                subtitle: "Analyze local crime trends",
                imagePath: "assets/images/stats.jpg",
                buttonText: "View Stats",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CrimeStatisticsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              DashboardCard(
                title: "Report Crime",
                subtitle: "Submit details anonymously",
                imagePath: "assets/images/crime.jpg",
                buttonText: "Report Now",
                onPressed: () {
                  // Navigate to report form
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Home Dashboard",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Icon(Icons.bar_chart, color: Colors.black),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
        BottomNavigationBarItem(
            icon: Icon(Icons.analytics), label: "Statistics"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ],
    );
  }
}
