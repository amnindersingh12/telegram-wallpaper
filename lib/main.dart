import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart';
import 'services/background_task_manager.dart';
import 'services/telegram_backend_service.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.backgroundColor,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  // Initialize services
  await BackgroundTaskManager.initialize();
  await TelegramBackendService.initialize();
  
  runApp(const TelegramWallpaperApp());
}

class TelegramWallpaperApp extends StatelessWidget {
  const TelegramWallpaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kabe Neko',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginScreen(),
    );
  }
}
