import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_scraper_service.dart';
import 'wallpaper_service.dart';

const String autoWallpaperTask = 'autoWallpaperTask';
const String autoWallpaperTaskUnique = 'autoWallpaperTaskUnique';

/// Background task callback - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('Background task executing: $task');
      
      if (task == autoWallpaperTask) {
        await _updateWallpaperInBackground();
      }
      
      return true;
    } catch (e) {
      print('Background task error: $e');
      return false;
    }
  });
}

Future<void> _updateWallpaperInBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final channelUsername = prefs.getString('channel_username');
    final isEnabled = prefs.getBool('auto_update_enabled') ?? false;
    final useTrueRandom = prefs.getBool('true_random') ?? true;
    
    if (!isEnabled || channelUsername == null || channelUsername.isEmpty) {
      print('Auto update disabled or no channel configured');
      return;
    }
    
    print('Fetching new wallpaper from channel: $channelUsername');
    
    // Fetch images from channel
    final scraper = TelegramScraperService(channelUsername: channelUsername);
    final images = await scraper.fetchChannelImages();
    
    if (images.isEmpty) {
      print('No images found');
      return;
    }
    
    // Get last wallpaper ID to avoid setting the same one
    final lastId = await WallpaperService.getLastWallpaperId();
    
    // Use secure random if enabled
    final random = useTrueRandom ? Random.secure() : Random();
    
    // Find a different image
    TelegramImage? selectedImage;
    if (lastId != null) {
      // Try to find a different image
      final differentImages = images.where((img) => img.messageId != lastId).toList();
      if (differentImages.isNotEmpty) {
        // Pick a random one from the different images
        selectedImage = differentImages[random.nextInt(differentImages.length)];
      }
    }
    
    // If no different image found, pick random from all
    selectedImage ??= images[random.nextInt(images.length)];
    
    // Get wallpaper location preference
    final location = await WallpaperService.getWallpaperLocation();
    
    // Set the wallpaper
    final success = await WallpaperService.setWallpaperFromUrl(
      selectedImage.fullUrl,
      location: location,
      messageId: selectedImage.messageId,
    );
    
    print('Wallpaper update ${success ? 'successful' : 'failed'}: ${selectedImage.messageId}');
  } catch (e) {
    print('Error updating wallpaper in background: $e');
  }
}

class BackgroundTaskManager {
  /// Check if background tasks are supported on current platform
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }
  
  /// Initialize WorkManager (Android only)
  static Future<void> initialize() async {
    if (!isSupported) {
      print('Background tasks not supported on this platform');
      return;
    }
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// Schedule periodic wallpaper updates (Android only)
  static Future<void> scheduleWallpaperUpdate({required int intervalMinutes}) async {
    if (!isSupported) {
      print('Background wallpaper updates not supported on this platform');
      return;
    }
    // Cancel existing task first
    await cancelWallpaperUpdate();
    
    // Register new periodic task
    await Workmanager().registerPeriodicTask(
      autoWallpaperTaskUnique,
      autoWallpaperTask,
      frequency: Duration(minutes: intervalMinutes),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
    
    print('Scheduled wallpaper update every $intervalMinutes minutes');
  }

  /// Cancel all scheduled tasks (Android only)
  static Future<void> cancelAllTasks() async {
    if (!isSupported) return;
    await Workmanager().cancelAll();
    print('Cancelled all scheduled tasks');
  }

  /// Cancel scheduled wallpaper updates (Android only)
  static Future<void> cancelWallpaperUpdate() async {
    if (!isSupported) return;
    await Workmanager().cancelByUniqueName(autoWallpaperTaskUnique);
    print('Cancelled scheduled wallpaper updates');
  }
  
  /// Start background task (alias for scheduleWallpaperUpdate)
  static Future<void> startBackgroundTask(int intervalMinutes) async {
    await scheduleWallpaperUpdate(intervalMinutes: intervalMinutes);
  }
  
  /// Stop background task (alias for cancelWallpaperUpdate)
  static Future<void> stopBackgroundTask() async {
    await cancelWallpaperUpdate();
  }

  /// Update wallpaper immediately (not in background)
  static Future<bool> updateWallpaperNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final channelUsername = prefs.getString('channel_username');
      final useTrueRandom = prefs.getBool('true_random') ?? true;
      
      if (channelUsername == null || channelUsername.isEmpty) {
        return false;
      }
      
      // Fetch images from channel
      final scraper = TelegramScraperService(channelUsername: channelUsername);
      final images = await scraper.fetchChannelImages();
      
      if (images.isEmpty) {
        return false;
      }
      
      // Get last wallpaper ID to avoid setting the same one
      final lastId = await WallpaperService.getLastWallpaperId();
      
      // Use secure random if enabled
      final random = useTrueRandom ? Random.secure() : Random();
      
      // Find a different image
      TelegramImage? selectedImage;
      if (lastId != null) {
        final differentImages = images.where((img) => img.messageId != lastId).toList();
        if (differentImages.isNotEmpty) {
          selectedImage = differentImages[random.nextInt(differentImages.length)];
        }
      }
      
      selectedImage ??= images[random.nextInt(images.length)];
      
      // Get wallpaper location preference
      final location = await WallpaperService.getWallpaperLocation();
      
      // Set the wallpaper
      return await WallpaperService.setWallpaperFromUrl(
        selectedImage.fullUrl,
        location: location,
        messageId: selectedImage.messageId,
      );
    } catch (e) {
      print('Error updating wallpaper: $e');
      return false;
    }
  }
}
