import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_wallpaper_manager/flutter_wallpaper_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

enum WallpaperLocation {
  homeScreen,
  lockScreen,
  both,
}

enum WallpaperCropMode {
  fill, // Crop to fill entire screen
  fit,  // Fit within screen, may have black bars
  stretch, // Stretch to fill (may distort)
}

class WallpaperService {
  static const String _lastWallpaperKey = 'last_wallpaper_url';
  static const String _lastWallpaperIdKey = 'last_wallpaper_id';
  static const String _updateIntervalKey = 'update_interval_minutes';
  static const String _autoUpdateEnabledKey = 'auto_update_enabled';
  static const String _wallpaperLocationKey = 'wallpaper_location';
  static const String _wallpaperCropModeKey = 'wallpaper_crop_mode';

  /// Get wallpaper crop mode preference
  static Future<WallpaperCropMode> getWallpaperCropMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_wallpaperCropModeKey) ?? 0;
    return WallpaperCropMode.values[index.clamp(0, WallpaperCropMode.values.length - 1)];
  }

  /// Set wallpaper crop mode preference
  static Future<void> setWallpaperCropMode(WallpaperCropMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wallpaperCropModeKey, mode.index);
  }

  /// Process image for screen size
  static Future<String?> processImageForScreen(
    String filePath, {
    required int screenWidth,
    required int screenHeight,
    WallpaperCropMode cropMode = WallpaperCropMode.fill,
  }) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) return filePath;
      
      img.Image processed;
      
      switch (cropMode) {
        case WallpaperCropMode.fill:
          // Crop to fill - maintains aspect ratio, crops excess
          processed = img.copyResizeCropSquare(image, size: screenWidth > screenHeight ? screenWidth : screenHeight);
          // Now resize to exact screen dimensions
          processed = img.copyResize(
            image,
            width: screenWidth,
            height: screenHeight,
            interpolation: img.Interpolation.cubic,
          );
          break;
          
        case WallpaperCropMode.fit:
          // Fit within bounds - maintains aspect ratio, adds letterboxing if needed
          final aspectRatio = image.width / image.height;
          final screenAspect = screenWidth / screenHeight;
          
          int newWidth, newHeight;
          if (aspectRatio > screenAspect) {
            newWidth = screenWidth;
            newHeight = (screenWidth / aspectRatio).round();
          } else {
            newHeight = screenHeight;
            newWidth = (screenHeight * aspectRatio).round();
          }
          
          final resized = img.copyResize(
            image,
            width: newWidth,
            height: newHeight,
            interpolation: img.Interpolation.cubic,
          );
          
          // Create black background and center the image
          processed = img.Image(width: screenWidth, height: screenHeight);
          img.fill(processed, color: img.ColorRgb8(0, 0, 0));
          
          final offsetX = (screenWidth - newWidth) ~/ 2;
          final offsetY = (screenHeight - newHeight) ~/ 2;
          img.compositeImage(processed, resized, dstX: offsetX, dstY: offsetY);
          break;
          
        case WallpaperCropMode.stretch:
          // Stretch to fill - ignores aspect ratio
          processed = img.copyResize(
            image,
            width: screenWidth,
            height: screenHeight,
            interpolation: img.Interpolation.cubic,
          );
          break;
      }
      
      // Save processed image
      final directory = await getApplicationDocumentsDirectory();
      final processedPath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final processedFile = File(processedPath);
      await processedFile.writeAsBytes(img.encodeJpg(processed, quality: 95));
      
      return processedPath;
    } catch (e) {
      print('Error processing image: $e');
      return filePath; // Return original if processing fails
    }
  }

  /// Download image from URL and return local file path
  static Future<String?> downloadImage(String imageUrl, {String? fileName}) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image: ${response.statusCode}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final name = fileName ?? 'wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${directory.path}/$name';
      
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      
      return filePath;
    } catch (e) {
      print('Error downloading image: $e');
      return null;
    }
  }

  /// Set wallpaper from a local file path (Android only)
  static Future<bool> setWallpaper(
    String filePath, {
    WallpaperLocation location = WallpaperLocation.both,
  }) async {
    // Wallpaper setting is only supported on Android
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      print('Wallpaper setting is only supported on Android');
      return false;
    }
    
    try {
      int locationValue;
      switch (location) {
        case WallpaperLocation.homeScreen:
          locationValue = WallpaperManager.HOME_SCREEN;
          break;
        case WallpaperLocation.lockScreen:
          locationValue = WallpaperManager.LOCK_SCREEN;
          break;
        case WallpaperLocation.both:
          locationValue = WallpaperManager.BOTH_SCREEN;
          break;
      }

      final result = await WallpaperManager.setWallpaperFromFile(
        filePath,
        locationValue,
      );
      
      return result;
    } on PlatformException catch (e) {
      print('Platform error setting wallpaper: $e');
      return false;
    } catch (e) {
      print('Error setting wallpaper: $e');
      return false;
    }
  }

  /// Download and set wallpaper from URL
  static Future<bool> setWallpaperFromUrl(
    String imageUrl, {
    WallpaperLocation location = WallpaperLocation.both,
    int? messageId,
  }) async {
    try {
      final filePath = await downloadImage(imageUrl);
      if (filePath == null) return false;

      final success = await setWallpaper(filePath, location: location);
      
      if (success) {
        // Save last wallpaper info
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastWallpaperKey, imageUrl);
        if (messageId != null) {
          await prefs.setInt(_lastWallpaperIdKey, messageId);
        }
      }
      
      return success;
    } catch (e) {
      print('Error setting wallpaper from URL: $e');
      return false;
    }
  }

  /// Set wallpaper from local file path (for backend downloads)
  static Future<bool> setWallpaperFromFile(
    String filePath, {
    WallpaperLocation location = WallpaperLocation.both,
    int? messageId,
  }) async {
    try {
      final success = await setWallpaper(filePath, location: location);
      
      if (success) {
        // Save last wallpaper info
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastWallpaperKey, filePath);
        if (messageId != null) {
          await prefs.setInt(_lastWallpaperIdKey, messageId);
        }
      }
      
      return success;
    } catch (e) {
      print('Error setting wallpaper from file: $e');
      return false;
    }
  }

  /// Set wallpaper from bytes (for backend downloaded images)
  static Future<bool> setWallpaperFromBytes(
    List<int> bytes, {
    WallpaperLocation location = WallpaperLocation.both,
    int? messageId,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      
      return setWallpaperFromFile(filePath, location: location, messageId: messageId);
    } catch (e) {
      print('Error setting wallpaper from bytes: $e');
      return false;
    }
  }

  /// Get saved update interval in minutes
  static Future<int> getUpdateInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_updateIntervalKey) ?? 60; // Default 1 hour
  }

  /// Set update interval in minutes
  static Future<void> setUpdateInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_updateIntervalKey, minutes);
  }

  /// Check if auto update is enabled
  static Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUpdateEnabledKey) ?? false;
  }

  /// Enable/disable auto update
  static Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdateEnabledKey, enabled);
  }

  /// Get wallpaper location preference
  static Future<WallpaperLocation> getWallpaperLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_wallpaperLocationKey) ?? 2;
    return WallpaperLocation.values[index];
  }

  /// Set wallpaper location preference
  static Future<void> setWallpaperLocation(WallpaperLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wallpaperLocationKey, location.index);
  }

  /// Get last set wallpaper message ID
  static Future<int?> getLastWallpaperId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastWallpaperIdKey);
  }

  /// Clean up old wallpaper files
  static Future<void> cleanupOldWallpapers() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      
      for (final file in files) {
        if (file is File && file.path.contains('wallpaper_')) {
          // Keep only the last 5 wallpapers
          final fileName = file.path.split('/').last;
          if (fileName.startsWith('wallpaper_')) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      print('Error cleaning up wallpapers: $e');
    }
  }
}
