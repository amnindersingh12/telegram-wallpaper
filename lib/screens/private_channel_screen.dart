import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../services/telegram_backend_service.dart';
import '../services/wallpaper_service.dart';
import 'settings_screen.dart';

class PrivateChannelScreen extends StatefulWidget {
  final JoinedChannel channel;

  const PrivateChannelScreen({
    super.key,
    required this.channel,
  });

  @override
  State<PrivateChannelScreen> createState() => _PrivateChannelScreenState();
}

class _PrivateChannelScreenState extends State<PrivateChannelScreen> {
  List<ChannelImage> _images = [];
  final Map<String, Uint8List> _thumbnailCache = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSettingWallpaper = false;
  String? _errorMessage;
  int? _currentWallpaperId;
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initService();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initService() async {
    await TelegramBackendService.initialize();
    _loadImages();
    _loadCurrentWallpaperId();
  }

  Future<void> _loadCurrentWallpaperId() async {
    final id = await WallpaperService.getLastWallpaperId();
    if (mounted) {
      setState(() => _currentWallpaperId = id);
    }
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
      _errorMessage = null;
    });

    try {
      final images = await TelegramBackendService.getChannelImages(
        widget.channel.identifier,
        limit: 50,
      );
      
      if (mounted) {
        setState(() {
          _images = images;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load images: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreImages() async {
    if (_isLoadingMore || _images.isEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final lastMessageId = _images.last.messageId;
      final moreImages = await TelegramBackendService.getChannelImages(
        widget.channel.identifier,
        limit: 50,
        offsetId: lastMessageId,
      );
      
      if (mounted && moreImages.isNotEmpty) {
        setState(() {
          final existingIds = _images.map((img) => img.messageId).toSet();
          final newImages = moreImages.where((img) => !existingIds.contains(img.messageId));
          _images.addAll(newImages);
        });
      }
    } catch (e) {
      debugPrint('Error loading more: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<Uint8List?> _getThumbnail(ChannelImage image) async {
    if (_thumbnailCache.containsKey(image.fileId)) {
      return _thumbnailCache[image.fileId];
    }

    try {
      final data = await TelegramBackendService.downloadImage(image.fileId);
      if (data != null && mounted) {
        setState(() {
          _thumbnailCache[image.fileId] = data;
        });
      }
      return data;
    } catch (e) {
      debugPrint('Error loading thumbnail: $e');
      return null;
    }
  }

  Future<void> _setWallpaper(ChannelImage image) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    setState(() => _isSettingWallpaper = true);
    
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Downloading and setting wallpaper...'),
          ],
        ),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      // Download full image
      final imageData = await TelegramBackendService.downloadImage(image.fileId);
      
      if (imageData == null) {
        throw Exception('Failed to download image');
      }

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/wallpaper_${image.messageId}.jpg');
      await tempFile.writeAsBytes(imageData);

      // Get wallpaper location preference
      final location = await WallpaperService.getWallpaperLocation();
      
      // Set the wallpaper
      final success = await WallpaperService.setWallpaperFromFile(
        tempFile.path,
        location: location,
        messageId: image.messageId,
      );

      scaffoldMessenger.hideCurrentSnackBar();
      
      if (success) {
        setState(() => _currentWallpaperId = image.messageId);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('✓ Wallpaper set successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to set wallpaper'),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSettingWallpaper = false);
      }
    }
  }

  Future<void> _setRandomWallpaper() async {
    if (_images.isEmpty) return;
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    setState(() => _isSettingWallpaper = true);
    
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Setting random wallpaper...'),
          ],
        ),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      // Check if true random is enabled
      final prefs = await SharedPreferences.getInstance();
      final useTrueRandom = prefs.getBool('true_random') ?? true;
      
      // Select random image
      ChannelImage randomImage;
      if (useTrueRandom) {
        final secureRandom = Random.secure();
        var pool = _images;
        if (_currentWallpaperId != null && _images.length > 1) {
          pool = _images.where((img) => img.messageId != _currentWallpaperId).toList();
        }
        randomImage = pool[secureRandom.nextInt(pool.length)];
      } else {
        randomImage = _images[Random().nextInt(_images.length)];
      }
      
      // Download full image
      final imageData = await TelegramBackendService.downloadImage(randomImage.fileId);
      
      if (imageData == null) {
        throw Exception('Failed to download image');
      }

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/wallpaper_${randomImage.messageId}.jpg');
      await tempFile.writeAsBytes(imageData);

      // Get wallpaper location preference
      final location = await WallpaperService.getWallpaperLocation();
      
      // Set the wallpaper
      final success = await WallpaperService.setWallpaperFromFile(
        tempFile.path,
        location: location,
        messageId: randomImage.messageId,
      );

      scaffoldMessenger.hideCurrentSnackBar();
      
      if (success) {
        setState(() => _currentWallpaperId = randomImage.messageId);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('✓ Random wallpaper set!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to set wallpaper'),
            backgroundColor: Colors.red,
          ),
        );
      }

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSettingWallpaper = false);
      }
    }
  }

  void _showImagePreview(ChannelImage image, Uint8List? imageData) {
    if (imageData == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.memory(
                  imageData,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSettingWallpaper ? null : () {
                        Navigator.pop(context);
                        _setWallpaper(image);
                      },
                      icon: const Icon(Icons.wallpaper),
                      label: const Text('Set Wallpaper'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.channel.title),
            Text(
              '${widget.channel.formattedMemberCount} members',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Set Random Wallpaper',
            onPressed: _isSettingWallpaper || _images.isEmpty ? null : _setRandomWallpaper,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadCurrentWallpaperId();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadImages,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_images.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No images found in this channel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return _buildImageTile(_images[index]);
            },
          ),
        ),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildImageTile(ChannelImage image) {
    final isCurrentWallpaper = _currentWallpaperId == image.messageId;
    
    return FutureBuilder<Uint8List?>(
      future: _getThumbnail(image),
      builder: (context, snapshot) {
        return GestureDetector(
          onTap: () {
            if (snapshot.data != null) {
              _showImagePreview(image, snapshot.data);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[300],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: snapshot.hasData && snapshot.data != null
                      ? Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        )
                      : snapshot.hasError
                          ? const Center(
                              child: Icon(Icons.error, color: Colors.red),
                            )
                          : const Center(
                              child: CircularProgressIndicator(),
                            ),
                ),
              ),
              if (isCurrentWallpaper)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _isSettingWallpaper ? null : () => _setWallpaper(image),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.wallpaper,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
