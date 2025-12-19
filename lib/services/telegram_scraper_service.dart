import 'package:http/http.dart' as http;

/// Service to fetch images from Telegram public channels
/// Uses t.me/s/ public preview which doesn't require authentication
class TelegramScraperService {
  final String channelUsername;
  
  TelegramScraperService({required this.channelUsername});
  
  /// Static convenience method to get channel images
  static Future<List<String>> getChannelImages(String channelUsername) async {
    final service = TelegramScraperService(channelUsername: channelUsername);
    final images = await service.fetchChannelImages();
    return images.map((img) => img.fullUrl).toList();
  }
  
  /// Fetches images from a public Telegram channel using t.me/s/ preview
  /// Returns list of image URLs
  Future<List<TelegramImage>> fetchChannelImages({int? beforeMessageId}) async {
    try {
      // Use t.me/s/ which provides public web preview of channels
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
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to load channel: ${response.statusCode}');
      }
      
      return _parseImages(response.body);
    } catch (e) {
      rethrow;
    }
  }
  
  /// Parse HTML response to extract image URLs
  List<TelegramImage> _parseImages(String html) {
    final List<TelegramImage> images = [];
    
    // Pattern to find background images in photo wraps
    // Example: <a href="https://t.me/channel/123" class="tgme_widget_message_photo_wrap" style="background-image:url('https://...')">
    final photoWrapPattern = RegExp(
      r'''href="https://t\.me/([^/]+)/(\d+)"[^>]*class="[^"]*tgme_widget_message_photo_wrap[^"]*"[^>]*style="[^"]*background-image:\s*url\(['"']([^'"]+)['"']\)''',
      multiLine: true,
    );
    
    for (final match in photoWrapPattern.allMatches(html)) {
      final channel = match.group(1);
      final messageId = int.tryParse(match.group(2) ?? '');
      var imageUrl = match.group(3);
      
      if (messageId != null && imageUrl != null && imageUrl.isNotEmpty) {
        imageUrl = _getHighResUrl(imageUrl);
        
        images.add(TelegramImage(
          messageId: messageId,
          thumbnailUrl: imageUrl,
          fullUrl: imageUrl,
          channelUsername: channel ?? channelUsername,
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
      var imageUrl = match.group(3);
      
      if (messageId != null && imageUrl != null && imageUrl.isNotEmpty) {
        // Skip if already added
        if (images.any((img) => img.messageId == messageId)) continue;
        
        imageUrl = _getHighResUrl(imageUrl);
        
        images.add(TelegramImage(
          messageId: messageId,
          thumbnailUrl: imageUrl,
          fullUrl: imageUrl,
          channelUsername: channel ?? channelUsername,
        ));
      }
    }
    
    // Third pattern: look for data-post attribute with background-image
    final dataPostPattern = RegExp(
      r'data-post="([^/]+)/(\d+)"',
      multiLine: true,
    );
    
    final bgImagePattern = RegExp(
      r'''background-image:\s*url\(['"']([^'"]+)['"']\)''',
      multiLine: true,
    );
    
    // Find all message blocks with data-post
    final messageBlockPattern = RegExp(
      r'<div[^>]*class="[^"]*tgme_widget_message[^"]*"[^>]*data-post="([^"]+)"[^>]*>',
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
        var imageUrl = bgMatch.group(1);
        if (imageUrl != null && imageUrl.isNotEmpty) {
          imageUrl = _getHighResUrl(imageUrl);
          
          images.add(TelegramImage(
            messageId: messageId,
            thumbnailUrl: imageUrl,
            fullUrl: imageUrl,
            channelUsername: channel,
          ));
        }
      }
    }
    
    // Sort by messageId descending (newest first)
    images.sort((a, b) => b.messageId.compareTo(a.messageId));
    
    return images;
  }
  
  /// Convert thumbnail URL to full resolution
  String _getHighResUrl(String url) {
    // Telegram image URLs sometimes have size parameters
    // Try to get the highest resolution
    return url;
  }
  
  /// Get channel info (title, description, photo)
  Future<ChannelInfo?> getChannelInfo() async {
    try {
      final url = 'https://t.me/s/$channelUsername';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      
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
      );
      final subscribersMatch = subscribersPattern.firstMatch(html);
      
      // Extract channel photo
      final photoPattern = RegExp(
        r'<img class="tgme_page_photo_image"[^>]*src="([^"]+)"',
      );
      final photoMatch = photoPattern.firstMatch(html);
      
      return ChannelInfo(
        username: channelUsername,
        title: titleMatch?.group(1) ?? channelUsername,
        subscriberCount: subscribersMatch?.group(1) ?? 'Unknown',
        photoUrl: photoMatch?.group(1),
      );
    } catch (e) {
      print('Error getting channel info: $e');
      return null;
    }
  }
}

class TelegramImage {
  final int messageId;
  final String thumbnailUrl;
  final String fullUrl;
  final String channelUsername;
  
  TelegramImage({
    required this.messageId,
    required this.thumbnailUrl,
    required this.fullUrl,
    required this.channelUsername,
  });
  
  String get postUrl => 'https://t.me/$channelUsername/$messageId';
}

class ChannelInfo {
  final String username;
  final String title;
  final String subscriberCount;
  final String? photoUrl;
  final String? description;
  
  ChannelInfo({
    required this.username,
    required this.title,
    required this.subscriberCount,
    this.photoUrl,
    this.description,
  });
}
