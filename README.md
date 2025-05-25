# SafeRoute - Smart Navigation App

## Project Overview
SafeRoute is a Flutter-based navigation application that provides smart routing solutions with a focus on user safety. The app helps users navigate through safer routes by considering various factors like crime statistics, traffic conditions, and user preferences.

### Key Features
- Smart route planning with safety considerations
- Real-time crime statistics and hotspot visualization
- User authentication and profile management
- Customizable map views and preferences
- Dark mode support
- Route history and saved locations
- Crime reporting system

## Setup Steps

### Prerequisites
- Flutter SDK (latest stable version)
- Dart SDK (latest stable version)
- Android Studio / VS Code
- Firebase account
- Google Maps API key

### Installation

1. **Clone the Repository**
   ```bash
   git clone https://github.com/your-username/SafeRoute-Project.git
   cd SafeRoute-Project
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Setup**
   - Create a new Firebase project
   - Add Android and iOS apps to your Firebase project
   - Download and add the configuration files:
     - `google-services.json` for Android
     - `GoogleService-Info.plist` for iOS
   - Enable Authentication and Firestore in Firebase Console

4. **Google Maps Setup**
   - Get a Google Maps API key from Google Cloud Console
   - Enable necessary APIs (Maps SDK, Directions API, Places API)
   - Add the API key to:
     - Android: `android/app/src/main/AndroidManifest.xml`
     - iOS: `ios/Runner/AppDelegate.swift`

5. **Environment Configuration**
   - Create a `.env` file in the root directory
   - Add your API keys and configuration:
     ```
     GOOGLE_MAPS_API_KEY=your_api_key_here
     ```

6. **Run the App**
   ```bash
   flutter run
   ```

### Project Structure
```
lib/
├── main.dart
├── providers/
│   ├── app_provider.dart
│   ├── user_provider.dart
│   └── settings_provider.dart
├── screens/
│   ├── home_dashboard.dart
│   ├── login_screen.dart
│   ├── map_screen.dart
│   └── ...
├── services/
│   ├── auth_service.dart
│   └── ...
├── utils/
│   └── firebase_auth_helper.dart
└── widgets/
    └── ...
```

### State Management
The app uses Provider pattern for state management with three main providers:
- AppProvider: General app state
- UserProvider: User authentication and profile
- SettingsProvider: App settings and preferences

### Contributing
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### License
This project is licensed under the MIT License - see the LICENSE file for details

### Contact
Your Name - your.email@example.com
Project Link: https://github.com/your-username/SafeRoute-Project