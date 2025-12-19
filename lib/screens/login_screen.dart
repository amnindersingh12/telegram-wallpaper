import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';
import 'channel_browser_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _channelController = TextEditingController();
  bool _isLoading = false;
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadSavedChannel();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _loadSavedChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final channel = prefs.getString('channel_username') ?? '';
    if (channel.isNotEmpty) {
      _channelController.text = channel;
    }
  }

  Future<void> _saveAndProceed() async {
    if (_channelController.text.isEmpty) {
      _showSnackBar('Please enter a channel username', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('channel_username', _channelController.text.trim());

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
        ),
      );
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

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
              Color(0xFF0D1117),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height - 
                              MediaQuery.of(context).padding.top - 
                              MediaQuery.of(context).padding.bottom - 
                              AppTheme.spacingL * 2,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: AppTheme.spacingXL),
                      _buildLogo(),
                      const SizedBox(height: AppTheme.spacingXL),
                      _buildTitle(),
                      const SizedBox(height: AppTheme.spacingS),
                      _buildSubtitle(),
                      const SizedBox(height: AppTheme.spacingXL),
                      _buildInputCard(),
                      const SizedBox(height: AppTheme.spacingM),
                      _buildStartButton(),
                      const SizedBox(height: AppTheme.spacingM),
                      _buildChannelBrowserButton(),
                      const SizedBox(height: AppTheme.spacingXL),
                      _buildBackendStatus(),
                      const SizedBox(height: AppTheme.spacingM),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.4),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Icon(
          Icons.wallpaper_rounded,
          size: 60,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
      child: const Text(
        'Wallpaper Magic',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return const Text(
      'Transform your screen with stunning wallpapers\nfrom Telegram channels you love \u2728',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        color: AppTheme.textSecondary,
        height: 1.6,
      ),
    );
  }

  Widget _buildInputCard() {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.alternate_email,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Your Favorite Channel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          TextField(
            controller: _channelController,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., wallpapers, aesthetics',
              prefixIcon: const Icon(Icons.tag, color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          const Text(
            'Just the username, no @ needed \ud83d\ude09',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        text: 'Let\'s Go!',
        icon: Icons.rocket_launch_rounded,
        isLoading: _isLoading,
        onPressed: _saveAndProceed,
      ),
    );
  }

  Widget _buildChannelBrowserButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const ChannelBrowserScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder: (_, animation, __, child) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
                    child: child,
                  ),
                );
              },
            ),
          );
        },
        icon: const Icon(Icons.explore_rounded),
        label: const Text('Explore My Channels'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: AppTheme.textMuted.withOpacity(0.3)),
        ),
      ),
    );
  }

  Widget _buildBackendStatus() {
    return Column(
      children: [
        AnimatedContainer(
          duration: AppTheme.animNormal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: AppTheme.successColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.successColor,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.successColor.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Ready for public channels',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.successColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _buildInfoCard(),
      ],
    );
  }

  Widget _buildInfoCard() {
    return GlassCard(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'How it works',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            '✓ Public channels work out of the box\n'
            '✓ Search and browse any public channel\n'
            '✗ NSFW/private channels require Telegram login\n',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.8,
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'For NSFW/private channels you\'ve joined, Telegram login will be available in a future update.',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}