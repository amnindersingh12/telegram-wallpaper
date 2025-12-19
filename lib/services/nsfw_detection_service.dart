import 'package:flutter/foundation.dart';

/// NSFW detection service - detects NSFW content based on multiple signals
class NSFWDetectionService {
  static const List<String> _nsfwKeywords = [
    'xxx',
    'porn',
    'adult',
    'nsfw',
    'explicit',
    'nude',
    '18+',
    '18 plus',
    '+18',
    'uncensored',
    'hentai',
    'ecchi',
    'adult content',
    'sexual',
  ];

  static const List<String> _nsfwChannelPatterns = [
    'porn',
    'adult',
    'xxx',
    'hot',
    'nude',
    'explicit',
    'uncensored',
  ];

  /// Detect if a channel is likely NSFW based on its name/title/description
  static bool isChannelLikelyNSFW(String channelName, String? title, String? description) {
    final searchText = '${channelName.toLowerCase()} ${title?.toLowerCase() ?? ''} ${description?.toLowerCase() ?? ''}'.trim();
    
    for (final keyword in _nsfwChannelPatterns) {
      if (searchText.contains(keyword)) {
        return true;
      }
    }
    
    return false;
  }

  /// Detect if an image is likely NSFW based on its caption
  static bool isImageLikelyNSFW(String? caption, String channelName) {
    if (caption == null) return false;
    
    final text = '${caption.toLowerCase()} ${channelName.toLowerCase()}'.trim();
    
    // Check for NSFW keywords
    for (final keyword in _nsfwKeywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    
    return false;
  }

  /// Heuristic: analyze image metadata for NSFW indicators
  static bool analyzeImageMetadata({
    required String? caption,
    required String channelName,
    required int? width,
    required int? height,
  }) {
    // Check caption for NSFW content
    if (isImageLikelyNSFW(caption, channelName)) {
      return true;
    }
    
    // Additional metadata checks could be added here
    // (width/height ratios commonly used for certain content, etc.)
    
    return false;
  }

  /// Score content based on multiple signals (0.0 - 1.0)
  static double calculateNSFWScore({
    required String? caption,
    required String channelName,
    required String? title,
    required String? description,
  }) {
    double score = 0.0;
    final maxScore = 1.0;

    // Channel-level indicators
    if (isChannelLikelyNSFW(channelName, title, description)) {
      score += 0.5;
    }

    // Image-level indicators
    if (caption != null && caption.isNotEmpty) {
      final text = caption.toLowerCase();
      
      for (final keyword in _nsfwKeywords) {
        if (text.contains(keyword)) {
          score += 0.3;
          break; // Count once per category
        }
      }
    }

    return score.clamp(0.0, maxScore);
  }

  /// Determine if content should be hidden based on score
  static bool shouldHideContent({required double nsfwScore, required bool nsfwFilterEnabled}) {
    if (!nsfwFilterEnabled) return false;
    
    // Hide if score indicates likely NSFW content
    return nsfwScore >= 0.3;
  }
}
