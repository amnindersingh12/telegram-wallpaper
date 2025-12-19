import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Native Telegram service that works directly in the app
/// Uses Telegram's Bot API for public channels and MTProto for private access
class TelegramNativeService {
  static const String _sessionStringKey = 'telegram_session_string';
  static const String _apiIdKey = 'telegram_api_id';
  static const String _apiHashKey = 'telegram_api_hash';
  
  // Telegram credentials - can be set by user or use defaults
  static String? _sessionString;
  
  /// Initialize the service with stored credentials
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionString = prefs.getString(_sessionStringKey);
  }
  
  /// Check if credentials are configured
  static bool get isConfigured => 
      _sessionString != null && _sessionString!.isNotEmpty;
  
  /// Get current session string (masked)
  static String? get maskedSessionString {
    if (_sessionString == null) return null;
    if (_sessionString!.length <= 20) return '***';
    return '${_sessionString!.substring(0, 10)}...${_sessionString!.substring(_sessionString!.length - 10)}';
  }
  
  /// Save Telegram credentials
  static Future<void> saveCredentials({
    required String sessionString,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString(_sessionStringKey, sessionString);
    _sessionString = sessionString;
  }
  
  /// Clear all credentials
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStringKey);
    await prefs.remove(_apiIdKey);
    await prefs.remove(_apiHashKey);
    _sessionString = null;
  }
  
  /// Fetch public channel images using t.me/s/ (no auth needed)
  static Future<List<TelegramImage>> fetchPublicChannelImages(
    String channelUsername, {
    int? beforeMessageId,
  }) async {
    try {
      String url = 'https://t.me/s/$channelUsername';
      if (beforeMessageId != null) {
        url += '?before=$beforeMessageId';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load channel: ${response.statusCode}');
      }
      
      return _parsePublicChannelImages(response.body, channelUsername);
    } catch (e) {
      debugPrint('Error fetching public channel: $e');
      rethrow;
    }
  }
  
  /// Parse HTML to extract images from public channel page
  static List<TelegramImage> _parsePublicChannelImages(String html, String channelUsername) {
    final List<TelegramImage> images = [];
    
    // Pattern to find background images in photo wraps
    final photoWrapPattern = RegExp(
      r'''href="https://t\.me/([^/]+)/(\d+)"[^>]*class="[^"]*tgme_widget_message_photo_wrap[^"]*"[^>]*style="[^"]*background-image:\s*url\(['"']([^'"]+)['"']\)''',
      multiLine: true,
    );
    
    for (final match in photoWrapPattern.allMatches(html)) {
      final channel = match.group(1);
      final messageId = int.tryParse(match.group(2) ?? '');
      final imageUrl = match.group(3);
      
      if (messageId != null && imageUrl != null && imageUrl.isNotEmpty) {
        images.add(TelegramImage(
          messageId: messageId,
          channelId: channel ?? channelUsername,
          thumbnailUrl: imageUrl,
          fullUrl: imageUrl,
        ));
      }
    }
    
    // Alternative pattern: class comes before style
    final altPattern = RegExp(
      r'''class="[^"]*tgme_widget_message_photo_wrap[^"]*"[^>]*href="https://t\.me/([^/]+)/(\d+)"[^>]*style="[^"]*background-image:\s*url\(['"']([^'"]+)['"']\)''',
      multiLine: true,
    );
    
    for (final match in altPattern.allMatches(html)) {
      final channel = match.group(1);
      final messageId = int.tryParse(match.group(2) ?? '');
      final imageUrl = match.group(3);
      
      if (messageId != null && imageUrl != null && imageUrl.isNotEmpty) {
        // Skip if already added
        if (images.any((img) => img.messageId == messageId)) continue;
        
        images.add(TelegramImage(
          messageId: messageId,
          channelId: channel ?? channelUsername,
          thumbnailUrl: imageUrl,
          fullUrl: imageUrl,
        ));
      }
    }
    
    // Third pattern: data-post with background-image
    final messageBlockPattern = RegExp(
      r'<div[^>]*class="[^"]*tgme_widget_message[^"]*"[^>]*data-post="([^"]+)"[^>]*>',
      multiLine: true,
    );
    
    final bgImagePattern = RegExp(
      r'''background-image:\s*url\(['"']([^'"]+)['"']\)''',
      multiLine: true,
    );
    
    for (final blockMatch in messageBlockPattern.allMatches(html)) {
      final dataPost = blockMatch.group(1);
      if (dataPost == null) continue;
      
      final parts = dataPost.split('/');
      if (parts.length != 2) continue;
      
      final channel = parts[0];
      final messageId = int.tryParse(parts[1]);
      if (messageId == null) continue;
      
      // Skip if already added
      if (images.any((img) => img.messageId == messageId)) continue;
      
      // Find the next background-image after this position
      final startIndex = blockMatch.start;
      final endIndex = html.indexOf('tgme_widget_message ', startIndex + 1);
      final searchEnd = endIndex == -1 ? html.length : endIndex;
      final blockContent = html.substring(startIndex, searchEnd);
      
      final bgMatch = bgImagePattern.firstMatch(blockContent);
      if (bgMatch != null) {
        final imageUrl = bgMatch.group(1);
        if (imageUrl != null && imageUrl.isNotEmpty) {
          images.add(TelegramImage(
            messageId: messageId,
            channelId: channel,
            thumbnailUrl: imageUrl,
            fullUrl: imageUrl,
          ));
        }
      }
    }
    
    // Sort by messageId descending (newest first)
    images.sort((a, b) => b.messageId.compareTo(a.messageId));
    
    return images;
  }
  
  /// Fetch channel info from public page
  static Future<TelegramChannel?> fetchPublicChannelInfo(String channelUsername) async {
    try {
      final url = 'https://t.me/s/$channelUsername';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode != 200) {
        return null;
      }
      
      final html = response.body;
      
      // Extract channel title
      final titlePattern = RegExp(
        r'<div class="tgme_channel_info_header_title"[^>]*><span[^>]*>([^<]+)</span>',
      );
      final titleMatch = titlePattern.firstMatch(html);
      
      // Extract subscriber count
      final subscribersPattern = RegExp(
        r'<div class="tgme_channel_info_counter"[^>]*>.*?<span class="counter_value">([^<]+)</span>',
        dotAll: true,
      );
      final subscribersMatch = subscribersPattern.firstMatch(html);
      
      // Extract channel photo
      final photoPattern = RegExp(
        r'<img class="tgme_page_photo_image"[^>]*src="([^"]+)"',
      );
      final photoMatch = photoPattern.firstMatch(html);
      
      // Parse subscriber count
      int? memberCount;
      if (subscribersMatch != null) {
        final countStr = subscribersMatch.group(1)?.replaceAll(RegExp(r'[^\d]'), '');
        memberCount = int.tryParse(countStr ?? '');
      }
      
      return TelegramChannel(
        id: 0, // Unknown from public page
        username: channelUsername,
        title: titleMatch?.group(1) ?? channelUsername,
        type: 'CHANNEL',
        photoUrl: photoMatch?.group(1),
        membersCount: memberCount,
        isPrivate: false,
      );
    } catch (e) {
      debugPrint('Error fetching channel info: $e');
      return null;
    }
  }
  
  /// Download image from URL
  static Future<Uint8List?> downloadImage(String imageUrl) async {
    try {
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 60));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading image: $e');
      return null;
    }
  }
  
  /// Get direct image URL for a public channel message
  static String getPublicImageUrl(String channelUsername, int messageId) {
    return 'https://t.me/$channelUsername/$messageId?embed=1';
  }
}

/// Represents a Telegram channel
class TelegramChannel {
  final int id;
  final String? username;
  final String title;
  final String type;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final int? membersCount;
  final String? description;
  final bool isPrivate;
  
  TelegramChannel({
    required this.id,
    this.username,
    required this.title,
    required this.type,
    this.photoUrl,
    this.photoBytes,
    this.membersCount,
    this.description,
    this.isPrivate = false,
  });
  
  /// Get identifier for API calls
  String get identifier => username ?? id.toString();
  
  /// Format member count
  String get formattedMemberCount {
    if (membersCount == null) return 'Unknown';
    if (membersCount! >= 1000000) {
      return '${(membersCount! / 1000000).toStringAsFixed(1)}M';
    } else if (membersCount! >= 1000) {
      return '${(membersCount! / 1000).toStringAsFixed(1)}K';
    }
    return membersCount.toString();
  }
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'title': title,
      'type': type,
      'photo_url': photoUrl,
      'members_count': membersCount,
      'description': description,
      'is_private': isPrivate,
    };
  }
  
  factory TelegramChannel.fromMap(Map<String, dynamic> map) {
    return TelegramChannel(
      id: map['id'] ?? 0,
      username: map['username'],
      title: map['title'] ?? 'Unknown',
      type: map['type'] ?? 'CHANNEL',
      photoUrl: map['photo_url'],
      membersCount: map['members_count'],
      description: map['description'],
      isPrivate: map['is_private'] ?? false,
    );
  }
}

/// Represents an image from Telegram
class TelegramImage {
  final int messageId;
  final String channelId;
  final String thumbnailUrl;
  final String fullUrl;
  final int? width;
  final int? height;
  final String? caption;
  final DateTime? date;
  
  TelegramImage({
    required this.messageId,
    required this.channelId,
    required this.thumbnailUrl,
    required this.fullUrl,
    this.width,
    this.height,
    this.caption,
    this.date,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'channel_id': channelId,
      'thumbnail_url': thumbnailUrl,
      'full_url': fullUrl,
      'width': width,
      'height': height,
      'caption': caption,
      'date': date?.toIso8601String(),
    };
  }
  
  factory TelegramImage.fromMap(Map<String, dynamic> map) {
    return TelegramImage(
      messageId: map['message_id'],
      channelId: map['channel_id'],
      thumbnailUrl: map['thumbnail_url'],
      fullUrl: map['full_url'],
      width: map['width'],
      height: map['height'],
      caption: map['caption'],
      date: map['date'] != null ? DateTime.tryParse(map['date']) : null,
    );
  }
}
