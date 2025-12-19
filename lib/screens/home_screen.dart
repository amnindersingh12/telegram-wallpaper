import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/app_theme.dart';
import '../utils/text_sanitizer.dart';
import '../services/telegram_scraper_service.dart';
import '../services/wallpaper_service.dart';
import '../services/telegram_backend_service.dart';
import '../services/wallpaper_history_service.dart';
import 'settings_screen.dart';
import 'channel_browser_screen.dart';
import 'wallpaper_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<String> _images = [];
  bool _isLoading = true;
  String _channelUsername = '';
  String _error = '';
  bool _usingBackend = false; // Track if we're using backend for this channel

  // Scroll and pagination
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreImages = true;
  int _lastMessageId = 0;
  static const int _pageSize = 50;
  List<dynamic> _backendImageData = []; // Store full image data for pagination

  late AnimationController _fadeController;
  late AnimationController _refreshController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadChannel();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    
    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 500) {
      _loadMoreImages();
    }
  }

  Future<void> _loadMoreImages() async {
    if (_isLoadingMore || !_hasMoreImages) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final newImages = await TelegramBackendService.getChannelImages(
        _channelUsername,
        limit: _pageSize,
        offsetId: _lastMessageId,
      );
      
      if (newImages.isEmpty) {
        setState(() => _hasMoreImages = false);
      } else {
        // Use the image URLs directly
        final newUrls = newImages.map((img) => img.imageUrl).where((url) => url.isNotEmpty).toList();
        
        _lastMessageId = newImages.last.messageId;
        
        setState(() {
          _images.addAll(newUrls);
          _backendImageData.addAll(newImages);
        });
      }
    } catch (e) {
      print('Error loading more images: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final channel = sanitizeText(prefs.getString('channel_username'));
    
    if (mounted) {
      setState(() => _channelUsername = channel);
      if (channel.isNotEmpty) {
        await _fetchImages();
      } else {
        setState(() {
          _isLoading = false;
          _error = 'No channel configured';
        });
      }
    }
  }

  Future<void> _fetchImages() async {
    if (_channelUsername.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _error = '';
      _usingBackend = false;
      _hasMoreImages = true;
      _lastMessageId = 0;
      _backendImageData = [];
    });

    try {
      // Try the public scraper for public channels
      final images = await TelegramScraperService.getChannelImages(_channelUsername);
      
      if (images.isNotEmpty) {
        if (mounted) {
          setState(() {
            _images = images;
            _isLoading = false;
          });
        }
        return;
      }
      
      // If scraper returns empty, try the integrated service
      try {
        final backendImages = await TelegramBackendService.getChannelImages(
          _channelUsername,
          limit: _pageSize,
          offsetId: 0,
        );
        if (backendImages.isNotEmpty && mounted) {
          _backendImageData = backendImages;
          _lastMessageId = backendImages.last.messageId;
          setState(() {
            _images = backendImages.map((img) => img.imageUrl).where((url) => url.isNotEmpty).toList();
            _isLoading = false;
            _usingBackend = true;
          });
          return;
        }
      } catch (_) {}
      
      // Both methods returned empty/failed
      if (mounted) {
        setState(() {
          _images = [];
          _isLoading = false;
          _error = 'No images found. This channel may be:\n• Private or NSFW (not accessible)\n• A user account (not a channel)\n• A channel without images';
        });
      }
    } catch (e) {
      // Scraper failed, try integrated service
      try {
        final backendImages = await TelegramBackendService.getChannelImages(
          _channelUsername,
          limit: _pageSize,
          offsetId: 0,
        );
        if (backendImages.isNotEmpty && mounted) {
          _backendImageData = backendImages;
          _lastMessageId = backendImages.last.messageId;
          setState(() {
            _images = backendImages.map((img) => img.imageUrl).where((url) => url.isNotEmpty).toList();
            _isLoading = false;
            _usingBackend = true;
          });
          return;
        }
      } catch (_) {}
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load images from channel.';
        });
      }
    }
  }

  Future<void> _setRandomWallpaper() async {
    if (_images.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final useTrueRandom = prefs.getBool('true_random') ?? false;

    final random = useTrueRandom ? Random.secure() : Random();
    final randomImage = _images[random.nextInt(_images.length)];

    // Auto-apply wallpaper directly
    await _setWallpaperDirectly(randomImage, isRandom: true);
  }

  Future<void> _setWallpaperDirectly(String imageUrl, {bool isRandom = false}) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                isRandom ? 'Applying surprise wallpaper... ✨' : 'Setting wallpaper...',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final success = await WallpaperService.setWallpaperFromUrl(imageUrl);
      
      if (success && mounted) {
        // Log to history
        await WallpaperHistoryService.addEntry(
          imageUrl: imageUrl,
          channelName: _channelUsername,
          source: isRandom ? 'random' : 'public',
        );
        
        Navigator.pop(context); // Close loading dialog
        _showSuccessAnimation();
      } else {
        Navigator.pop(context);
        _showSnackBar('Failed to set wallpaper', isError: true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Failed to set wallpaper: $e', isError: true);
      }
    }
  }

  void _showSuccessAnimation() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: const Icon(
                    Icons.check_circle,
                    color: AppTheme.successColor,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            const Text('Wallpaper set successfully!'),
          ],
        ),
        backgroundColor: AppTheme.cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError ? AppTheme.errorColor : AppTheme.primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.cardColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  void _showImagePreview(String imageUrl, {bool isRandom = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ImagePreviewSheet(
        imageUrl: imageUrl,
        channelName: _channelUsername,
        isRandom: isRandom,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _fadeController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _error.isNotEmpty
                          ? _buildErrorState()
                          : _images.isEmpty
                              ? _buildEmptyState()
                              : _buildImageGrid(),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wallpapers',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.alternate_email,
                              size: 14,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _channelUsername.isEmpty
                                    ? 'No channel'
                                    : _channelUsername,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_images.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildHeaderAction(
            icon: Icons.folder_special_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ChannelBrowserScreen(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildHeaderAction(
            icon: Icons.history_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WallpaperHistoryScreen(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildHeaderAction(
            icon: Icons.settings_rounded,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadChannel();
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderAction(
            icon: Icons.refresh_rounded,
            onTap: () {
              _refreshController.repeat();
              _fetchImages().then((_) => _refreshController.stop());
            },
            child: RotationTransition(
              turns: _refreshController,
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: child ?? Icon(icon, color: AppTheme.textPrimary, size: 22),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          const Text(
            'Finding beautiful wallpapers... ✨',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hang tight, magic is happening!',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'Oops! We hit a bump 🙈',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Don\'t worry, these things happen.\nLet\'s give it another shot!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            GradientButton(
              text: 'Try Again',
              icon: Icons.refresh_rounded,
              onPressed: _fetchImages,
            ),
          ],
        ),
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
                color: AppTheme.warningColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 48,
                color: AppTheme.warningColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'Channel needs backend access 🔐',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This channel has restricted content (NSFW/private).\nMake sure the backend server is running!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            GradientButton(
              text: 'Try with Backend',
              icon: Icons.rocket_launch_rounded,
              onPressed: _fetchImages,
            ),
            const SizedBox(height: AppTheme.spacingM),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChannelBrowserScreen(),
                ),
              ),
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Browse My Channels'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    // Calculate total item count including loading indicator
    final itemCount = _images.length + (_usingBackend && _hasMoreImages ? 1 : 0);
    
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Loading indicator at bottom
        if (index >= _images.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoadingMore
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    )
                  : const SizedBox(),
            ),
          );
        }
        
        return AnimatedListItem(
          index: index,
          child: _usingBackend
              ? _BackendImageCard(
                  imageUrl: _images[index],
                  onTap: () => _showImagePreview(_images[index]),
                )
              : _ImageCard(
                  imageUrl: _images[index],
                  onTap: () => _showImagePreview(_images[index]),
                ),
        );
      },
    );
  }

  Widget _buildFAB() {
    if (_images.isEmpty) return const SizedBox();
    
    return FloatingActionButton(
      onPressed: _setRandomWallpaper,
      backgroundColor: AppTheme.primaryColor,
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
    );
  }
}

class _ImageCard extends StatefulWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _ImageCard({
    required this.imageUrl,
    required this.onTap,
  });

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildShimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceColor,
      highlightColor: AppTheme.cardColor,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 400,
                  maxWidthDiskCache: 600,
                  fadeInDuration: const Duration(milliseconds: 200),
                  httpHeaders: const {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Referer': 'https://t.me/',
                  },
                  placeholder: (context, url) => _buildShimmerPlaceholder(),
                  errorWidget: (context, url, error) => Container(
                    color: AppTheme.surfaceColor,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_rounded,
                          color: AppTheme.textMuted,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to retry',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Image card for backend URLs - uses direct URL loading
class _BackendImageCard extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const _BackendImageCard({
    required this.imageUrl,
    required this.onTap,
  });

  Widget _buildShimmerPlaceholder() {
    return Shimmer.fromColors(
      baseColor: AppTheme.surfaceColor,
      highlightColor: AppTheme.cardColor,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get thumbnail URL by adding ?thumbnail=true
    final thumbnailUrl = imageUrl.contains('?') 
        ? '$imageUrl&thumbnail=true' 
        : '$imageUrl?thumbnail=true';
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: CachedNetworkImage(
            imageUrl: thumbnailUrl,
            fit: BoxFit.cover,
            memCacheWidth: 400,
            maxWidthDiskCache: 600,
            fadeInDuration: const Duration(milliseconds: 200),
            httpHeaders: const {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Referer': 'https://t.me/',
            },
            placeholder: (context, url) => _buildShimmerPlaceholder(),
            errorWidget: (context, url, error) => Container(
              color: AppTheme.surfaceColor,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported_rounded,
                    color: AppTheme.textMuted,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to retry',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewSheet extends StatefulWidget {
  final String imageUrl;
  final String channelName;
  final bool isRandom;

  const _ImagePreviewSheet({
    required this.imageUrl,
    required this.channelName,
    required this.isRandom,
  });

  @override
  State<_ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<_ImagePreviewSheet> {
  bool _isSettingWallpaper = false;

  Future<void> _setWallpaper() async {
    setState(() => _isSettingWallpaper = true);
    
    try {
      final success = await WallpaperService.setWallpaperFromUrl(widget.imageUrl);
      
      if (success && mounted) {
        // Log to history
        await WallpaperHistoryService.addEntry(
          imageUrl: widget.imageUrl,
          channelName: widget.channelName,
          source: widget.isRandom ? 'random' : 'public',
        );
        
        Navigator.pop(context); // Close preview sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.successColor),
                SizedBox(width: 12),
                Text('Wallpaper set successfully! \u2728'),
              ],
            ),
            backgroundColor: AppTheme.cardColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to set wallpaper'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSettingWallpaper = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXLarge),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Row(
              children: [
                if (widget.isRandom)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shuffle, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Random Pick',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                  httpHeaders: const {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Referer': 'https://t.me/',
                  },
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: AppTheme.textMuted,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    text: _isSettingWallpaper ? 'Setting...' : 'Set Wallpaper',
                    icon: Icons.wallpaper_rounded,
                    isLoading: _isSettingWallpaper,
                    onPressed: _setWallpaper,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
