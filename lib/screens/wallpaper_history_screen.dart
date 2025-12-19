import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/app_theme.dart';
import '../utils/text_sanitizer.dart';
import '../services/wallpaper_history_service.dart';
import '../services/wallpaper_service.dart';

class WallpaperHistoryScreen extends StatefulWidget {
  const WallpaperHistoryScreen({super.key});

  @override
  State<WallpaperHistoryScreen> createState() => _WallpaperHistoryScreenState();
}

class _WallpaperHistoryScreenState extends State<WallpaperHistoryScreen> {
  List<WallpaperHistoryEntry> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await WallpaperHistoryService.getHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: const Text(
          'Clear History? 🗑️',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This will remove all wallpaper history entries.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WallpaperHistoryService.clearHistory();
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('History cleared'),
            backgroundColor: AppTheme.cardColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
          ),
        );
      }
    }
  }

  Future<void> _reapplyWallpaper(WallpaperHistoryEntry entry) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
        ),
      ),
    );

    try {
      bool success;
      if (entry.source == 'private' && entry.channelId != null && entry.messageId != null) {
        // For private channels, we'd need to re-download from backend
        // For now, if we have the URL (file path), try to use it
        success = await WallpaperService.setWallpaperFromFile(entry.imageUrl);
      } else {
        success = await WallpaperService.setWallpaperFromUrl(entry.imageUrl);
      }

      if (mounted) {
        Navigator.pop(context);
        
        if (success) {
          // Update history with new timestamp
          await WallpaperHistoryService.addEntry(
            imageUrl: entry.imageUrl,
            channelName: entry.channelName,
            channelId: entry.channelId,
            messageId: entry.messageId,
            source: entry.source,
          );
          await _loadHistory();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppTheme.successColor),
                  SizedBox(width: 12),
                  Text('Wallpaper reapplied! ✨'),
                ],
              ),
              backgroundColor: AppTheme.cardColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to apply wallpaper'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getSourceLabel(String source) {
    switch (source) {
      case 'random':
        return '🎲 Random';
      case 'private':
        return '🔒 Private';
      case 'public':
        return '🌐 Public';
      default:
        return '📷 Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                        ),
                      )
                    : _history.isEmpty
                        ? _buildEmptyState()
                        : _buildHistoryList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: AppTheme.textPrimary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallpaper History 📜',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${_history.length} wallpapers applied',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_history.isNotEmpty)
            GestureDetector(
              onTap: _clearHistory,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.errorColor,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'No history yet! 📝',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Applied wallpapers will appear here.\nGo set some beautiful wallpapers!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final entry = _history[index];
        return _HistoryCard(
          entry: entry,
          formatDate: _formatDate,
          getSourceLabel: _getSourceLabel,
          onReapply: () => _reapplyWallpaper(entry),
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final WallpaperHistoryEntry entry;
  final String Function(DateTime) formatDate;
  final String Function(String) getSourceLabel;
  final VoidCallback onReapply;

  const _HistoryCard({
    required this.entry,
    required this.formatDate,
    required this.getSourceLabel,
    required this.onReapply,
  });

  @override
  Widget build(BuildContext context) {
    final isNetworkImage = entry.imageUrl.startsWith('http');
    final safeChannelName = sanitizeText(entry.channelName);
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppTheme.radiusMedium),
              bottomLeft: Radius.circular(AppTheme.radiusMedium),
            ),
            child: SizedBox(
              width: 80,
              height: 100,
              child: isNetworkImage
                  ? CachedNetworkImage(
                      imageUrl: entry.imageUrl,
                      fit: BoxFit.cover,
                      httpHeaders: const {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                        'Referer': 'https://t.me/',
                      },
                      placeholder: (context, url) => Container(
                        color: AppTheme.surfaceColor,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppTheme.surfaceColor,
                        child: const Icon(
                          Icons.broken_image,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    )
                  : Container(
                      color: AppTheme.surfaceColor,
                      child: const Icon(
                        Icons.image_rounded,
                        color: AppTheme.textMuted,
                      ),
                    ),
            ),
          ),
          
          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          getSourceLabel(entry.source),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDate(entry.appliedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    safeChannelName.isEmpty ? 'Unknown Channel' : safeChannelName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Applied ${formatDate(entry.appliedAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Reapply button
          if (entry.imageUrl.startsWith('http'))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onReapply,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.replay_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
