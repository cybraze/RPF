import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'utils/theme_provider.dart';
import 'services/network_status_service.dart';
import 'services/tracking_service.dart';
import 'screens/splash_screen.dart';
import 'utils/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  // Must be called before runApp for task<->main communication
  FlutterForegroundTask.initCommunicationPort();

  // Configure the foreground service notification and task options
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'rpf_tracking_channel',
      channelName: 'RPF Location Tracking',
      channelDescription: 'Tracks constable GPS location during duty',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Check tracking state every 10 seconds.
      eventAction: ForegroundTaskEventAction.repeat(10000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  final trackingService = TrackingService();
  trackingService.initCallbacks();
  final networkStatusService = NetworkStatusService();
  networkStatusService.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => themeProvider),
        ChangeNotifierProvider(create: (_) => trackingService),
        ChangeNotifierProvider(create: (_) => networkStatusService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: SessionManager.navigatorKey,
      themeMode: themeProvider.themeMode,

      /// LIGHT THEME
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),

      /// DARK THEME
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1F3A),
      ),

      home: const SplashScreen(),
    );
  }
}
