import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'ui/screens/main_screen.dart';
import 'ui/screens/home_dashboard.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/register_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/map_screen.dart';

import 'providers/user_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/app_provider.dart';
import 'utils/firebase_auth_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase Auth Helper
  await FirebaseAuthHelper.initialize();

  // Check if user is logged in
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({Key? key, required this.isLoggedIn}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          // Initialize settings
          Future.delayed(Duration.zero, () {
            settingsProvider.loadSettings();
          });

          return MaterialApp(
            title: 'SafeRoute',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: true,
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xFF686DF1)),
              scaffoldBackgroundColor: Colors.white,
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF2D3748),
                elevation: 0,
              ),
            ),
            darkTheme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF686DF1),
                brightness: Brightness.dark,
              ),
              scaffoldBackgroundColor: Color(0xFF121212),
              appBarTheme: AppBarTheme(
                backgroundColor: Color(0xFF121212),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
            themeMode:
                settingsProvider.darkMode ? ThemeMode.dark : ThemeMode.light,
            initialRoute: '/splash',
            routes: {
              '/splash': (context) => SplashScreen(isLoggedIn: isLoggedIn),
              '/': (context) => const MainScreen(),
              '/home': (context) => const HomeDashboard(),
              '/login': (context) => LoginScreen(),
              '/register': (context) => RegisterScreen(),
              '/map': (context) => MapScreen(),
            },
          );
        },
      ),
    );
  }
}
