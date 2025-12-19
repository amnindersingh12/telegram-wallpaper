import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/text_sanitizer.dart';

/// Model for a wallpaper history entry
class WallpaperHistoryEntry {
  final String id;
  final String imageUrl;
  final String? channelName;
  final String? channelId;
  final int? messageId;
  final DateTime appliedAt;
  final String source; // 'public', 'private', 'random'

  WallpaperHistoryEntry({
    required this.id,
    required this.imageUrl,
    this.channelName,
    this.channelId,
    this.messageId,
    required this.appliedAt,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'imageUrl': imageUrl,
    'channelName': channelName,
    'channelId': channelId,
    'messageId': messageId,
    'appliedAt': appliedAt.toIso8601String(),
    'source': source,
  };

  factory WallpaperHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WallpaperHistoryEntry(
      id: json['id'],
      imageUrl: json['imageUrl'],
      channelName: sanitizeText(json['channelName']),
      channelId: json['channelId'],
      messageId: json['messageId'],
      appliedAt: DateTime.parse(json['appliedAt']),
      source: json['source'] ?? 'unknown',
    );
  }
}

/// Service to manage wallpaper application history
class WallpaperHistoryService {
  static const String _historyKey = 'wallpaper_history';
  static const int _maxHistoryItems = 50;

  /// Get all history entries
  static Future<List<WallpaperHistoryEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    
    return historyJson
        .map((json) => WallpaperHistoryEntry.fromJson(jsonDecode(json)))
        .toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt)); // Most recent first
  }

  /// Add a new history entry
  static Future<void> addEntry({
    required String imageUrl,
    String? channelName,
    String? channelId,
    int? messageId,
    required String source,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    
    final entry = WallpaperHistoryEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      imageUrl: imageUrl,
      channelName: sanitizeText(channelName),
      channelId: channelId,
      messageId: messageId,
      appliedAt: DateTime.now(),
      source: source,
    );
    
    // Add new entry at the beginning
    historyJson.insert(0, jsonEncode(entry.toJson()));
    
    // Keep only max items
    final trimmed = historyJson.take(_maxHistoryItems).toList();
    
    await prefs.setStringList(_historyKey, trimmed);
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  /// Get history count
  static Future<int> getHistoryCount() async {
    final history = await getHistory();
    return history.length;
  }

  /// Get the most recent entry
  static Future<WallpaperHistoryEntry?> getMostRecent() async {
    final history = await getHistory();
    return history.isNotEmpty ? history.first : null;
  }
}
