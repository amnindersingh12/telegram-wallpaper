import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_native_service.dart';

/// Unified Telegram service with multiple fallback methods
/// 1. Web embed API (og:image) - works for many channels including some NSFW
/// 2. Public scraper (t.me/s/) - for public non-NSFW channels
class TelegramBackendService {
  static const String _backendUrlKey = 'telegram_backend_url';
  
  // Default backend URLs - tries these in order
  static const List<String> _defaultBackendUrls = [
    'http://localhost:5000',
    'http://127.0.0.1:5000',
    'http://10.0.2.2:5000', // Android emulator
  ];
  
  static String? _cachedBackendUrl;
  static bool _urlInitialized = false;
  
  /// Initialize the service
  static Future<void> initialize() async {
    await TelegramNativeService.initialize();
    
    // Initialize backend URL
    await _initializeBackendUrl();
  }
  
  /// Initialize backend URL - tries to use saved URL, then defaults
  static Future<void> _initializeBackendUrl() async {
    if (_urlInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Check if user has set a custom URL
    final savedUrl = prefs.getString(_backendUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _cachedBackendUrl = savedUrl;
      _urlInitialized = true;
      debugPrint('Using saved backend URL: $savedUrl');
      return;
    }
    
    // Try to auto-detect working backend URL
    for (final url in _defaultBackendUrls) {
      try {
        final response = await http.get(
          Uri.parse('$url/health'),
          headers: {'Connection': 'close'},
        ).timeout(const Duration(seconds: 2));
        
        if (response.statusCode == 200) {
          _cachedBackendUrl = url;
          // Auto-save the working URL
          await prefs.setString(_backendUrlKey, url);
          debugPrint('Auto-detected backend URL: $url');
          _urlInitialized = true;
          return;
        }
      } catch (e) {
        debugPrint('Backend URL $url not available: $e');
      }
    }
    
    // If no URL works, use first default as fallback
    _cachedBackendUrl = _defaultBackendUrls.first;
    _urlInitialized = true;
    debugPrint('Using default backend URL: $_cachedBackendUrl');
  }
  
  /// Service is always available
  static Future<bool> isAvailable() async => true;
  static bool get hasSession => true;
  
  /// Set backend URL
  static Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, url);
    _cachedBackendUrl = url;
    debugPrint('Backend URL set to: $url');
  }
  
  /// Get backend URL
  static Future<String?> getBackendUrl() async {
    if (_cachedBackendUrl != null) {
      return _cachedBackendUrl;
    }
    
    if (!_urlInitialized) {
      await _initializeBackendUrl();
    }
    
    return _cachedBackendUrl;
  }
  
  /// Get all joined channels (private and public) from backend
  static Future<List<JoinedChannel>> fetchJoinedChannelsFromBackend({
    bool includePhotos = true,
  }) async {
    try {
      final backendUrl = await getBackendUrl();
      if (backendUrl == null || backendUrl.isEmpty) {
        debugPrint('Backend URL not configured');
        return await _getCachedJoinedChannels();
      }
      
      debugPrint('Fetching joined channels from: $backendUrl/channels');
      
      final url = Uri.parse('$backendUrl/channels?photos=${includePhotos ? 'true' : 'false'}');
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true && json['channels'] is List) {
          final channels = (json['channels'] as List)
              .whereType<Map<String, dynamic>>()
              .map((item) => JoinedChannel.fromJson(item))
              .toList();
          
          debugPrint('Successfully loaded ${channels.length} joined channels');
          
          // Cache the channels locally
          await _cacheJoinedChannels(channels);
          
          return channels;
        }
      } else {
        debugPrint('Backend returned status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching joined channels from backend: $e');
    }
    
    // Fallback to cached channels
    debugPrint('Falling back to cached channels');
    return _getCachedJoinedChannels();
  }
  
  /// Cache joined channels locally
  static Future<void> _cacheJoinedChannels(List<JoinedChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = channels.map((c) => c.toMap()).toList();
    await prefs.setString('cached_joined_channels', jsonEncode(jsonList));
  }
  
  /// Get cached joined channels
  static Future<List<JoinedChannel>> _getCachedJoinedChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('cached_joined_channels') ?? '[]';
    
    try {
      final List<dynamic> savedList = jsonDecode(savedJson);
      return savedList
          .whereType<Map<String, dynamic>>()
          .map((item) => JoinedChannel.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('Error loading cached joined channels: $e');
      return [];
    }
  }
  
  /// Get saved channels (for backward compatibility)
  static Future<List<JoinedChannel>> getJoinedChannels({bool includePhotos = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('saved_channels') ?? '[]';
    
    try {
      final List<dynamic> savedList = jsonDecode(savedJson);
      return savedList
          .whereType<Map<String, dynamic>>()
          .map((item) => JoinedChannel.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('Error loading saved channels: $e');
      return [];
    }
  }
  
  /// Get images from a channel - uses multiple methods
  static Future<List<ChannelImage>> getChannelImages(
    String channelId, {
    int limit = 50,
    int offsetId = 0,
  }) async {
    // Method 1: Try public scraper first (fastest)
    try {
      final images = await TelegramNativeService.fetchPublicChannelImages(
        channelId,
        beforeMessageId: offsetId > 0 ? offsetId : null,
      );
      
      if (images.isNotEmpty) {
        return images.take(limit).map((img) => ChannelImage(
          messageId: img.messageId,
          fileId: img.fullUrl,
          fileUniqueId: '${img.channelId}_${img.messageId}',
          channelId: channelId,
          width: img.width,
          height: img.height,
          caption: img.caption,
          date: img.date?.toIso8601String(),
        )).toList();
      }
    } catch (e) {
      debugPrint('Public scraper failed: $e');
    }
    
    // Method 2: Try web embed method (works for some restricted channels)
    try {
      final embedImages = await _fetchViaWebEmbed(channelId, limit: limit, startId: offsetId);
      if (embedImages.isNotEmpty) {
        return embedImages;
      }
    } catch (e) {
      debugPrint('Embed method failed: $e');
    }
    
    return [];
  }
  
  /// Fetch images via Telegram's web embed (og:image meta tags)
  /// This can work for some channels that block t.me/s/
  static Future<List<ChannelImage>> _fetchViaWebEmbed(
    String channelId, {
    int limit = 50,
    int startId = 0,
  }) async {
    final List<ChannelImage> images = [];
    int failures = 0;
    int maxFailures = 20; // Stop after 20 consecutive failures
    
    // Start from recent messages and go backwards
    int currentId = startId > 0 ? startId : 10000; // Start high and work down
    
    while (images.length < limit && failures < maxFailures) {
      try {
        final imageUrl = await _getEmbedImage(channelId, currentId);
        if (imageUrl != null && imageUrl.isNotEmpty) {
          // Check if we already have this image (avoid duplicates)
          if (!images.any((img) => img.fileId == imageUrl)) {
            images.add(ChannelImage(
              messageId: currentId,
              fileId: imageUrl,
              fileUniqueId: '${channelId}_$currentId',
              channelId: channelId,
            ));
            failures = 0; // Reset failure counter on success
          }
        } else {
          failures++;
        }
      } catch (e) {
        failures++;
      }
      
      currentId--;
      if (currentId <= 0) break;
      
      // Small delay to avoid rate limiting
      if (images.length % 5 == 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    
    return images;
  }
  
  /// Get single image URL from embed page
  static Future<String?> _getEmbedImage(String channelId, int messageId) async {
    try {
      final response = await http.get(
        Uri.parse('https://t.me/$channelId/$messageId?embed=1'),
        headers: {
          'User-Agent': 'TelegramBot (like TwitterBot)',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final html = response.body;
        
        // Look for og:image meta tag
        final ogMatch = RegExp(r'<meta property="og:image" content="([^"]+)"').firstMatch(html);
        if (ogMatch != null) {
          final url = ogMatch.group(1);
          // Filter out default/placeholder images
          if (url != null && 
              url.isNotEmpty && 
              !url.contains('telegram-logo') &&
              !url.contains('og_image') &&
              (url.contains('cdn') || url.contains('.jpg') || url.contains('.png') || url.contains('.webp'))) {
            return url;
          }
        }
        
        // Also check for background-image in photo wrap
        final bgRegex = RegExp(r'background-image:\s*url\(([^)]+)\)');
        final bgMatch = bgRegex.firstMatch(html);
        if (bgMatch != null) {
          final bgUrl = bgMatch.group(1)?.replaceAll("'", '').replaceAll('"', '');
          if (bgUrl != null && bgUrl.contains('cdn')) {
            return bgUrl;
          }
        }
      }
    } catch (e) {
      // Silently fail for individual messages
    }
    return null;
  }
  
  /// Download image by URL
  static Future<Uint8List?> downloadImage(String fileIdOrUrl) async {
    if (fileIdOrUrl.startsWith('http')) {
      return await TelegramNativeService.downloadImage(fileIdOrUrl);
    }
    return null;
  }
  
  /// Download image from channel and message
  static Future<Uint8List?> downloadFromMessage(
    String channelId, 
    int messageId, {
    bool thumbnail = false,
  }) async {
    try {
      // Try embed method first
      final embedUrl = await _getEmbedImage(channelId, messageId);
      if (embedUrl != null) {
        return await TelegramNativeService.downloadImage(embedUrl);
      }
      
      // Fallback to public scraper
      final images = await TelegramNativeService.fetchPublicChannelImages(
        channelId,
        beforeMessageId: messageId + 1,
      );
      
      final image = images.firstWhere(
        (img) => img.messageId == messageId,
        orElse: () => throw Exception('Image not found'),
      );
      
      return await TelegramNativeService.downloadImage(
        thumbnail ? image.thumbnailUrl : image.fullUrl,
      );
    } catch (e) {
      debugPrint('Error downloading from message: $e');
      return null;
    }
  }
  
  /// Get thumbnail URL
  static String getThumbnailUrl(String channelId, int messageId) {
    return 'https://t.me/$channelId/$messageId?embed=1';
  }
  
  /// Get full image URL
  static String getImageUrl(String channelId, int messageId) {
    return 'https://t.me/$channelId/$messageId?embed=1';
  }
  
  /// Search for channels
  static Future<List<JoinedChannel>> searchChannels(String query) async {
    try {
      final channelInfo = await TelegramNativeService.fetchPublicChannelInfo(query);
      if (channelInfo != null) {
        return [JoinedChannel(
          id: channelInfo.id,
          username: channelInfo.username,
          title: channelInfo.title,
          type: channelInfo.type,
          membersCount: channelInfo.membersCount,
          photoUrl: channelInfo.photoUrl,
        )];
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    return [];
  }
  
  /// Add channel to saved
  static Future<void> addSavedChannel(JoinedChannel channel) async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('saved_channels') ?? '[]';
    
    try {
      final List<dynamic> savedList = jsonDecode(savedJson);
      final exists = savedList.any((item) => 
        item is Map && (item['username'] == channel.username || item['id'] == channel.id)
      );
      
      if (!exists) {
        savedList.add(channel.toMap());
        await prefs.setString('saved_channels', jsonEncode(savedList));
      }
    } catch (e) {
      debugPrint('Error saving channel: $e');
    }
  }
  
  /// Remove channel from saved
  static Future<void> removeSavedChannel(String usernameOrId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('saved_channels') ?? '[]';
    
    try {
      final List<dynamic> savedList = jsonDecode(savedJson);
      savedList.removeWhere((item) => 
        item is Map && (item['username'] == usernameOrId || item['id'].toString() == usernameOrId)
      );
      await prefs.setString('saved_channels', jsonEncode(savedList));
    } catch (e) {
      debugPrint('Error removing channel: $e');
    }
  }
}

class JoinedChannel {
  final int id;
  final String? username;
  final String title;
  final String type;
  final String? photoBase64;
  final String? photoUrl;
  final int? membersCount;
  final String? description;
  
  JoinedChannel({
    required this.id,
    this.username,
    required this.title,
    required this.type,
    this.photoBase64,
    this.photoUrl,
    this.membersCount,
    this.description,
  });
  
  factory JoinedChannel.fromJson(Map<String, dynamic> json) {
    return JoinedChannel(
      id: json['id'] ?? 0,
      username: json['username'],
      title: json['title'] ?? 'Unknown',
      type: json['type'] ?? 'CHANNEL',
      photoBase64: json['photo_base64'],
      photoUrl: json['photo_url'],
      membersCount: json['members_count'],
      description: json['description'],
    );
  }
  
  String get identifier => username ?? id.toString();
  bool get isPrivate => username == null || username!.isEmpty;
  
  Uint8List? get photoBytes {
    if (photoBase64 == null) return null;
    try {
      return base64Decode(photoBase64!);
    } catch (e) {
      return null;
    }
  }
  
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
      'photo_base64': photoBase64,
      'photo_url': photoUrl,
      'members_count': membersCount,
      'description': description,
    };
  }
}

class ChannelImage {
  final int messageId;
  final String fileId;
  final String fileUniqueId;
  final int? width;
  final int? height;
  final String? date;
  final String? caption;
  final String channelId;
  final String? fileName;
  
  ChannelImage({
    required this.messageId,
    required this.fileId,
    required this.fileUniqueId,
    this.width,
    this.height,
    this.date,
    this.caption,
    required this.channelId,
    this.fileName,
  });
  
  factory ChannelImage.fromJson(Map<String, dynamic> json, String channelId) {
    return ChannelImage(
      messageId: json['message_id'],
      fileId: json['file_id'] ?? json['full_url'] ?? '',
      fileUniqueId: json['file_unique_id'] ?? '${channelId}_${json['message_id']}',
      width: json['width'],
      height: json['height'],
      date: json['date'],
      caption: json['caption'],
      channelId: channelId,
      fileName: json['file_name'],
    );
  }
  
  String get imageUrl => fileId.startsWith('http') ? fileId : '';
  
  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'file_id': fileId,
      'file_unique_id': fileUniqueId,
      'width': width,
      'height': height,
      'date': date,
      'caption': caption,
      'channel_id': channelId,
      'file_name': fileName,
    };
  }
}
