import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import '../services/background_task_manager.dart';
import '../services/wallpaper_service.dart';
import '../services/telegram_backend_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  
  String _channelUsername = '';
  int _intervalMinutes = 1;
  int _intervalSeconds = 0;
  bool _autoChangeEnabled = false;
  bool _trueRandom = false;
  bool _wifiOnly = false;
  WallpaperCropMode _cropMode = WallpaperCropMode.fill;
  String _backendUrl = '';

  final _channelController = TextEditingController();
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();
  final _backendUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _channelUsername = prefs.getString('channel_username') ?? '';
      _intervalMinutes = prefs.getInt('interval_minutes') ?? 15;
      _intervalSeconds = prefs.getInt('interval_seconds') ?? 0;
      _autoChangeEnabled = prefs.getBool('auto_change_enabled') ?? false;
      _trueRandom = prefs.getBool('true_random') ?? false;
      _wifiOnly = prefs.getBool('wifi_only') ?? false;
      
      _channelController.text = _channelUsername;
      _minutesController.text = _intervalMinutes.toString();
      _secondsController.text = _intervalSeconds.toString();
    });
    
    // Load backend URL
    final backendUrl = await TelegramBackendService.getBackendUrl();
    if (mounted) {
      setState(() {
        _backendUrl = backendUrl ?? '';
        _backendUrlController.text = _backendUrl;
      });
    }
    
    // Load crop mode
    final cropMode = await WallpaperService.getWallpaperCropMode();
    if (mounted) {
      setState(() => _cropMode = cropMode);
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;
    final totalSeconds = (minutes * 60) + seconds;
    
    // Minimum 15 minutes for background task (Android WorkManager limitation)
    if (_autoChangeEnabled && minutes < 15) {
      _showSnackBar('Minimum interval is 15 minutes for background tasks', isError: true);
      return;
    }
    
    await prefs.setString('channel_username', _channelController.text.trim());
    await prefs.setInt('interval_minutes', minutes);
    await prefs.setInt('interval_seconds', seconds);
    await prefs.setBool('auto_change_enabled', _autoChangeEnabled);
    await prefs.setBool('true_random', _trueRandom);
    await prefs.setBool('wifi_only', _wifiOnly);
    await WallpaperService.setWallpaperCropMode(_cropMode);
    
    // Save backend URL
    if (_backendUrlController.text.isNotEmpty) {
      await TelegramBackendService.setBackendUrl(_backendUrlController.text.trim());
    }
    
    if (_autoChangeEnabled) {
      // Use minutes directly (minimum 15 min for WorkManager)
      final intervalMinutes = minutes.clamp(15, 9999);
      await BackgroundTaskManager.startBackgroundTask(intervalMinutes);
    } else {
      await BackgroundTaskManager.stopBackgroundTask();
    }
    
    _showSnackBar('Settings saved!');
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
    _channelController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Column(
                      children: [
                        _buildChannelSection(),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildAutoChangeSection(),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildIntervalSection(),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildBackendSection(),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildOptionsSection(),
                        const SizedBox(height: AppTheme.spacingL),
                        _buildSaveButton(),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildLogoutButton(),
                        const SizedBox(height: AppTheme.spacingXL),
                      ],
                    ),
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
          const Text(
            'Preferences \u2699\ufe0f',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelSection() {
    return _SettingsCard(
      title: 'Your Channel',
      icon: Icons.favorite_rounded,
      child: TextField(
        controller: _channelController,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Which channel inspires you?',
          prefixIcon: Icon(Icons.tag, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  Widget _buildAutoChangeSection() {
    return _SettingsCard(
      title: 'Magic Auto-Change \u2728',
      icon: Icons.auto_awesome_rounded,
      trailing: Switch(
        value: _autoChangeEnabled,
        onChanged: (value) => setState(() => _autoChangeEnabled = value),
        activeColor: AppTheme.primaryColor,
      ),
      child: Text(
        _autoChangeEnabled
            ? 'Your wallpaper will refresh automatically!'
            : 'Turn on to keep your screen fresh',
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildIntervalSection() {
    return AnimatedOpacity(
      opacity: _autoChangeEnabled ? 1.0 : 0.5,
      duration: AppTheme.animNormal,
      child: _SettingsCard(
        title: 'How Often?',
        icon: Icons.schedule_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _IntervalInput(
                    controller: _minutesController,
                    label: 'Minutes',
                    enabled: _autoChangeEnabled,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'min',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.warningColor, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Android requires minimum 15 minutes for background tasks',
                      style: TextStyle(
                        color: AppTheme.warningColor,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickPresets(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPresets() {
    final presets = [
      {'label': '15m', 'min': 15},
      {'label': '30m', 'min': 30},
      {'label': '1h', 'min': 60},
      {'label': '2h', 'min': 120},
      {'label': '6h', 'min': 360},
      {'label': '12h', 'min': 720},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((preset) {
        final isSelected = _intervalMinutes == preset['min'];
        
        return GestureDetector(
          onTap: _autoChangeEnabled
              ? () {
                  setState(() {
                    _intervalMinutes = preset['min'] as int;
                    _minutesController.text = _intervalMinutes.toString();
                  });
                }
              : null,
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: isSelected ? AppTheme.primaryGradient : null,
              color: isSelected ? null : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? null
                  : Border.all(color: AppTheme.textMuted.withOpacity(0.2)),
            ),
            child: Text(
              preset['label'] as String,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBackendSection() {
    return _SettingsCard(
      title: 'Backend Server 🖥️',
      icon: Icons.storage_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your backend server URL to load joined channels (private and public)',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backendUrlController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.100:5000',
              prefixIcon: const Icon(Icons.link, color: AppTheme.textMuted),
              suffixIcon: _backendUrlController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textMuted),
                      onPressed: () {
                        _backendUrlController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Example: http://192.168.1.100:5000 or http://your-backend.com',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      children: [
        _SettingsCard(
          title: 'Wallpaper Fit 📐',
          icon: Icons.crop_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How should wallpapers fit your screen?',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCropModeChip(WallpaperCropMode.fill, 'Fill', 'Crop to fill'),
                  _buildCropModeChip(WallpaperCropMode.fit, 'Fit', 'Show entire image'),
                  _buildCropModeChip(WallpaperCropMode.stretch, 'Stretch', 'Stretch to fill'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _SettingsCard(
          title: 'True Random 🎲',
          icon: Icons.casino_rounded,
          trailing: Switch(
            value: _trueRandom,
            onChanged: (value) => setState(() => _trueRandom = value),
            activeColor: AppTheme.primaryColor,
          ),
          child: const Text(
            'Super secure randomization for the adventurous',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _SettingsCard(
          title: 'WiFi Only 📶',
          icon: Icons.wifi_rounded,
          trailing: Switch(
            value: _wifiOnly,
            onChanged: (value) => setState(() => _wifiOnly = value),
            activeColor: AppTheme.primaryColor,
          ),
          child: const Text(
            'Save your data - only download on WiFi',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildCropModeChip(WallpaperCropMode mode, String label, String subtitle) {
    final isSelected = _cropMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _cropMode = mode),
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected ? null : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: AppTheme.textMuted.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? Colors.white70 : AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        text: 'Save My Preferences ✔️',
        icon: Icons.check_circle_rounded,
        onPressed: _saveSettings,
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              ),
              title: const Text(
                'Start Fresh? \ud83c\udf31',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              content: const Text(
                'This will clear everything and take you back to the beginning.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep Everything'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          );
          
          if (confirm == true) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            await BackgroundTaskManager.stopBackgroundTask();
            
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          }
        },
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Start Over'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.errorColor,
          side: BorderSide(color: AppTheme.errorColor.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
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
                child: Icon(icon, color: AppTheme.primaryColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _IntervalInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int max;

  const _IntervalInput({
    required this.controller,
    required this.label,
    required this.enabled,
    this.max = 999,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _MaxValueFormatter(max),
          ],
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            filled: true,
            fillColor: AppTheme.surfaceColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  
  _MaxValueFormatter(this.max);
  
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    
    final value = int.tryParse(newValue.text);
    if (value == null) return oldValue;
    if (value > max) {
      return TextEditingValue(
        text: max.toString(),
        selection: TextSelection.collapsed(offset: max.toString().length),
      );
    }
    return newValue;
  }
}
