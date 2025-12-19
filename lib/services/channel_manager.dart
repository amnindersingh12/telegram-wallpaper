import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage saved channels and favorites
class ChannelManager {
  static const String _savedChannelsKey = 'saved_channels';
  static const String _favoriteChannelsKey = 'favorite_channels';
  static const String _recentChannelsKey = 'recent_channels';
  
  /// Save a channel to the list (accepts Map for flexibility)
  static Future<void> saveChannel(Map<String, dynamic> channel) async {
    final prefs = await SharedPreferences.getInstance();
    final channels = await getSavedChannels();
    
    final id = channel['id']?.toString() ?? channel['username'];
    
    // Remove if already exists to update
    channels.removeWhere((c) {
      final existingId = c['id']?.toString() ?? c['username'];
      return existingId == id;
    });
    channels.insert(0, channel);
    
    // Keep only last 50 channels
    if (channels.length > 50) {
      channels.removeLast();
    }
    
    await prefs.setString(_savedChannelsKey, jsonEncode(channels));
  }
  
  /// Get all saved channels as Maps
  static Future<List<Map<String, dynamic>>> getSavedChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_savedChannelsKey);
    
    if (jsonStr == null) return [];
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error loading saved channels: $e');
      return [];
    }
  }
  
  /// Remove a channel from saved list by id or username
  static Future<void> removeChannel(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final channels = await getSavedChannels();
    
    channels.removeWhere((c) {
      final id = c['id']?.toString() ?? c['username'];
      return id == identifier || c['username'] == identifier;
    });
    
    await prefs.setString(_savedChannelsKey, jsonEncode(channels));
  }
  
  /// Toggle favorite status
  static Future<bool> toggleFavorite(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoriteChannelsKey) ?? [];
    
    if (favorites.contains(identifier)) {
      favorites.remove(identifier);
      await prefs.setStringList(_favoriteChannelsKey, favorites);
      return false;
    } else {
      favorites.add(identifier);
      await prefs.setStringList(_favoriteChannelsKey, favorites);
      return true;
    }
  }
  
  /// Check if channel is favorite
  static Future<bool> isFavorite(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoriteChannelsKey) ?? [];
    return favorites.contains(identifier);
  }
  
  /// Get favorite channels
  static Future<List<Map<String, dynamic>>> getFavoriteChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoriteChannelsKey) ?? [];
    final allChannels = await getSavedChannels();
    
    return allChannels.where((c) {
      final id = c['id']?.toString() ?? c['username'];
      return favorites.contains(id);
    }).toList();
  }
  
  /// Add to recent channels
  static Future<void> addToRecent(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentChannelsKey) ?? [];
    
    recent.remove(identifier);
    recent.insert(0, identifier);
    
    // Keep only last 10 recent
    if (recent.length > 10) {
      recent.removeLast();
    }
    
    await prefs.setStringList(_recentChannelsKey, recent);
  }
  
  /// Get recent channel usernames
  static Future<List<String>> getRecentChannels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentChannelsKey) ?? [];
  }
}
