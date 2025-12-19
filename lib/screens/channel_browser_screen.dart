import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/app_theme.dart';
import '../services/telegram_backend_service.dart';
import '../services/channel_manager.dart';
import '../services/wallpaper_service.dart';
import '../services/wallpaper_history_service.dart';
import '../utils/text_sanitizer.dart';
import 'home_screen.dart';

class ChannelBrowserScreen extends StatefulWidget {
  const ChannelBrowserScreen({super.key});

  @override
  State<ChannelBrowserScreen> createState() => _ChannelBrowserScreenState();
}

class _ChannelBrowserScreenState extends State<ChannelBrowserScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _fadeController;
  
  List<Map<String, dynamic>> _savedChannels = [];
  List<Map<String, dynamic>> _joinedChannels = [];
  List<Map<String, dynamic>> _searchResults = [];
  
  bool _isSearching = false;
  bool _isLoadingJoined = false;
  
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    
    _loadSavedChannels();
    _loadJoinedChannels();
  }

  Future<void> _loadSavedChannels() async {
    final saved = await ChannelManager.getSavedChannels();
    if (mounted) {
      setState(() => _savedChannels = saved);
    }
  }

  Future<void> _loadJoinedChannels() async {
    setState(() => _isLoadingJoined = true);
    
    try {
      final joined = await TelegramBackendService.fetchJoinedChannelsFromBackend(
        includePhotos: true,
      );
      if (mounted) {
        setState(() {
          _joinedChannels = joined.map((c) => c.toMap()).toList();
          _isLoadingJoined = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading joined channels: $e');
      if (mounted) {
        setState(() => _isLoadingJoined = false);
      }
    }
  }

  Future<void> _searchChannels(String query) async {
    if (query.length < 2) return;
    
    setState(() => _isSearching = true);
    
    try {
      final results = await TelegramBackendService.searchChannels(query);
      if (mounted) {
        setState(() {
          _searchResults = results.map((c) => c.toMap()).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? AppTheme.errorColor : AppTheme.successColor,
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

  Future<void> _selectChannel(Map<String, dynamic> channel) async {
    final username = sanitizeText(channel['username'] as String?);
    
    if (username.isNotEmpty) {
      // Save channel to saved list
      await ChannelManager.saveChannel(channel);
      
      // Set as active channel and go to home
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('channel_username', username);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      _showSnackBar('Only public channels with usernames are supported', isError: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _searchController.dispose();
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
            colors: [Color(0xFF0D1117), Color(0xFF161B22)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: Column(
              children: [
                _buildHeader(),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSavedTab(),
                      _buildJoinedTab(),
                      _buildSearchTab(),
                    ],
                  ),
                ),
              ],
            ),
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
                  'My Channels',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    _buildStatusDot(true),
                    const SizedBox(width: 6),
                    const Text(
                      'Public channels ready',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadSavedChannels,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(bool isOnline) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? AppTheme.successColor : AppTheme.textMuted,
        boxShadow: isOnline
            ? [
                BoxShadow(
                  color: AppTheme.successColor.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        tabs: const [
          Tab(text: 'Saved'),
          Tab(text: 'Joined'),
          Tab(text: 'Search'),
        ],
      ),
    );
  }

  Widget _buildSavedTab() {
    if (_savedChannels.isEmpty) {
      return _buildAddChannelMessage();
    }
    
    return _buildChannelList(_savedChannels, showRemove: true);
  }

  Widget _buildJoinedTab() {
    if (_isLoadingJoined) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_joinedChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppTheme.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'No joined channels',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            const Text(
              'Backend server may not be running',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
              onPressed: _loadJoinedChannels,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    
    return _buildChannelList(_joinedChannels, showRemove: false);
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: TextField(
            controller: _searchController,
            onSubmitted: _searchChannels,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search channels...',
              prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      color: AppTheme.primaryColor,
                      onPressed: () => _searchChannels(_searchController.text),
                    ),
            ),
          ),
        ),
        Expanded(
          child: _searchResults.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_rounded,
                  title: 'Ready to discover? \ud83d\udd0e',
                  subtitle: 'Type a name to find amazing channels',
                )
              : _buildChannelList(_searchResults),
        ),
      ],
    );
  }

  Widget _buildAddChannelMessage() {
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
                Icons.add_circle_outline_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'Add your first channel! 🎨',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Go to the Search tab and find\namazing wallpaper channels',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: AppTheme.spacingL),
            GradientButton(
              text: 'Search Channels',
              icon: Icons.search,
              onPressed: () {
                _tabController.animateTo(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
          ),
          SizedBox(height: AppTheme.spacingM),
          Text(
            'Loading channels...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
              child: Icon(icon, size: 48, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelList(List<Map<String, dynamic>> channels,
      {bool showRemove = false}) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return AnimatedListItem(
          index: index,
          child: _ChannelCard(
            channel: channel,
            onTap: () => _selectChannel(channel),
            onSave: showRemove ? null : () => _saveChannel(channel),
            onRemove: showRemove ? () => _removeChannel(channel) : null,
          ),
        );
      },
    );
  }

  Future<void> _saveChannel(Map<String, dynamic> channel) async {
    await ChannelManager.saveChannel(channel);
    await _loadSavedChannels();
    _showSnackBar('Added to favorites! \u2764\ufe0f');
  }

  Future<void> _removeChannel(Map<String, dynamic> channel) async {
    final id = channel['id']?.toString() ?? channel['username'];
    if (id != null) {
      await ChannelManager.removeChannel(id);
      await _loadSavedChannels();
      _showSnackBar('Removed from favorites');
    }
  }
}

class _ChannelCard extends StatelessWidget {
  final Map<String, dynamic> channel;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final VoidCallback? onRemove;

  const _ChannelCard({
    required this.channel,
    required this.onTap,
    this.onSave,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final rawTitle = sanitizeText(channel['title'] as String?);
    final title = rawTitle.isEmpty ? 'Unknown' : rawTitle;
    final username = sanitizeText(channel['username'] as String?);
    final photoBase64 = channel['photo_base64'] as String?;
    final membersCount = channel['members_count'];
    final isPrivate = username.isEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(title, photoBase64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrivate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock,
                                size: 10,
                                color: AppTheme.warningColor,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'Private',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.warningColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (username.isNotEmpty)
                        Flexible(
                          child: Text(
                            '@$username',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.primaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (membersCount != null) ...[
                        if (username != null && username.isNotEmpty)
                          const Text(' • ', style: TextStyle(color: AppTheme.textMuted)),
                        Text(
                          _formatMemberCount(membersCount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onSave != null)
              IconButton(
                onPressed: onSave,
                icon: const Icon(Icons.bookmark_add_outlined),
                color: AppTheme.textMuted,
                iconSize: 20,
              ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.errorColor,
                iconSize: 20,
              ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String title, String? photoBase64) {
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(photoBase64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }
    
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatMemberCount(dynamic count) {
    if (count == null) return '';
    final num = count is int ? count : int.tryParse(count.toString()) ?? 0;
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M members';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K members';
    }
    return '$num members';
  }
}

class _PrivateChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelTitle;

  const _PrivateChannelScreen({
    required this.channelId,
    required this.channelTitle,
  });

  @override
  State<_PrivateChannelScreen> createState() => _PrivateChannelScreenState();
}

class _PrivateChannelScreenState extends State<_PrivateChannelScreen> {
  List<Map<String, dynamic>> _images = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreImages = true;
  int _lastMessageId = 0;
  final Map<String, Uint8List> _thumbnailCache = {};
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadImages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 500) {
      _loadMoreImages();
    }
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _images = [];
      _lastMessageId = 0;
      _hasMoreImages = true;
    });
    
    try {
      final images = await TelegramBackendService.getChannelImages(
        widget.channelId,
        limit: _pageSize,
      );
      if (mounted) {
        setState(() {
          _images = images.map((i) => i.toMap()).toList();
          _isLoading = false;
          _hasMoreImages = images.length >= _pageSize;
          if (_images.isNotEmpty) {
            _lastMessageId = _images.last['message_id'] ?? 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load images: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreImages() async {
    if (_isLoadingMore || !_hasMoreImages || _lastMessageId == 0) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final images = await TelegramBackendService.getChannelImages(
        widget.channelId,
        limit: _pageSize,
        offsetId: _lastMessageId,
      );
      
      if (mounted) {
        setState(() {
          final newImages = images.map((i) => i.toMap()).toList();
          _images.addAll(newImages);
          _isLoadingMore = false;
          _hasMoreImages = images.length >= _pageSize;
          if (newImages.isNotEmpty) {
            _lastMessageId = newImages.last['message_id'] ?? 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<Uint8List?> _loadThumbnail(Map<String, dynamic> image) async {
    final messageId = image['message_id']?.toString() ?? '';
    if (_thumbnailCache.containsKey(messageId)) {
      return _thumbnailCache[messageId];
    }
    
    try {
      final bytes = await TelegramBackendService.downloadFromMessage(
        widget.channelId,
        int.parse(messageId),
        thumbnail: true,
      );
      if (bytes != null) {
        _thumbnailCache[messageId] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setWallpaper(Map<String, dynamic> image, {bool isRandom = false}) async {
    final messageId = image['message_id'];
    if (messageId == null) return;

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
                isRandom ? 'Applying surprise wallpaper... \u2728' : 'Setting wallpaper...',
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
      final bytes = await TelegramBackendService.downloadFromMessage(
        widget.channelId,
        messageId,
      );
      
      if (bytes != null && mounted) {
        final success = await WallpaperService.setWallpaperFromBytes(bytes, messageId: messageId);
        
        if (success) {
          // Log to history
          await WallpaperHistoryService.addEntry(
            imageUrl: TelegramBackendService.getImageUrl(widget.channelId, messageId),
            channelName: widget.channelTitle,
            channelId: widget.channelId,
            messageId: messageId,
            source: isRandom ? 'random' : 'private',
          );
        }
        
        Navigator.pop(context); // Close loading dialog only
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.successColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isRandom 
                          ? 'Surprise! \u2728 New wallpaper applied!'
                          : 'Looking good! Wallpaper applied successfully',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.cardColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to download image'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
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
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Discovering wallpapers... \u2728',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : _images.isEmpty
                        ? _buildEmptyState()
                        : _buildImageGrid(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _images.isNotEmpty ? _buildFAB() : null,
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
                Icons.image_search_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            const Text(
              'No wallpapers found here \ud83d\udd0d',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This channel might not have any images yet,\nor they\'re still loading. Try refreshing!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            GradientButton(
              text: 'Refresh',
              icon: Icons.refresh_rounded,
              onPressed: _loadImages,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: _setRandomWallpaper,
      backgroundColor: AppTheme.primaryColor,
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
    );
  }
  
  Future<void> _setRandomWallpaper() async {
    if (_images.isEmpty) return;
    
    final random = _images[DateTime.now().millisecondsSinceEpoch % _images.length];
    await _setWallpaper(random, isRandom: true);
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
                Text(
                  widget.channelTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      '${_images.length} images',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    if (_hasMoreImages && !_isLoadingMore)
                      const Text(
                        ' • Scroll for more',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _loadImages,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.textPrimary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _images.length + (_isLoadingMore ? 2 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at the bottom
        if (index >= _images.length) {
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              ),
            ),
          );
        }
        
        final image = _images[index];
        final messageId = image['message_id'];
        final thumbnailUrl = TelegramBackendService.getThumbnailUrl(widget.channelId, messageId);
        
        return AnimatedListItem(
          index: index,
          child: _PrivateImageCard(
            thumbnailUrl: thumbnailUrl,
            onTap: () => _setWallpaper(image),
          ),
        );
      },
    );
  }
}

class _PrivateImageCard extends StatelessWidget {
  final String thumbnailUrl;
  final VoidCallback onTap;

  const _PrivateImageCard({
    required this.thumbnailUrl,
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
