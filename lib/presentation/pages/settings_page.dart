import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

class SettingsPage extends StatelessWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onClearHistory;
  final VoidCallback onClearFavorites;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.onClearHistory,
    required this.onClearFavorites,
  });

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _shareApp() {
    Share.share(
      'Check out MrPlay - Your Video Hub! ${AppConstants.shareAppUrl}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFFE8EAF6), const Color(0xFFF5F5F5)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Settings list
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Appearance Section
                    _buildSectionHeader(context, 'Appearance'),
                    const SizedBox(height: 8),
                    _buildThemeSelector(context),

                    const SizedBox(height: 24),

                    // Data Section
                    _buildSectionHeader(context, 'Data'),
                    const SizedBox(height: 8),
                    _buildMenuTile(
                      context,
                      icon: Icons.favorite_outline,
                      title: 'Favorites',
                      subtitle: 'View and manage your favorites',
                      onTap: () => Navigator.pushNamed(context, '/favorites'),
                    ),
                    _buildDivider(),
                    _buildMenuTile(
                      context,
                      icon: Icons.history,
                      title: 'Clear History',
                      subtitle: 'Remove all browsing history',
                      onTap: () => _showConfirmDialog(
                        context,
                        'Clear History',
                        'Are you sure you want to clear your browsing history?',
                        onClearHistory,
                      ),
                    ),
                    _buildDivider(),
                    _buildMenuTile(
                      context,
                      icon: Icons.delete_outline,
                      title: 'Clear Favorites',
                      subtitle: 'Remove all saved favorites',
                      onTap: () => _showConfirmDialog(
                        context,
                        'Clear Favorites',
                        'Are you sure you want to remove all favorites?',
                        onClearFavorites,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // About Section
                    _buildSectionHeader(context, 'About'),
                    const SizedBox(height: 8),
                    _buildInfoTile(
                      context,
                      icon: Icons.info_outline,
                      title: 'Version',
                      subtitle: AppConstants.appVersion,
                    ),
                    _buildDivider(),
                    _buildMenuTile(
                      context,
                      icon: Icons.description_outlined,
                      title: 'Privacy Policy',
                      subtitle: 'Read our privacy policy',
                      onTap: () => _launchUrl(AppConstants.privacyPolicyUrl),
                    ),
                    _buildDivider(),
                    _buildMenuTile(
                      context,
                      icon: Icons.star_outline,
                      title: 'Rate App',
                      subtitle: 'Love MrPlay? Leave a rating!',
                      onTap: () => _launchUrl(AppConstants.shareAppUrl),
                    ),
                    _buildDivider(),
                    _buildMenuTile(
                      context,
                      icon: Icons.share_outlined,
                      title: 'Share App',
                      subtitle: 'Tell your friends about MrPlay',
                      onTap: _shareApp,
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.primaryEnd,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.cardBackground.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.cardBorder.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: currentThemeMode == ThemeMode.dark,
            onChanged: (value) {
              onThemeModeChanged(value ? ThemeMode.dark : ThemeMode.light);
            },
            secondary: Icon(
              currentThemeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
              color: isDark ? Colors.amber.shade300 : Colors.orange,
            ),
            title: Text(
              currentThemeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              currentThemeMode == ThemeMode.dark
                  ? 'Using dark theme'
                  : 'Using light theme',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
            activeTrackColor: AppColors.primaryEnd,
          ),
          if (currentThemeMode != ThemeMode.system)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: GestureDetector(
                onTap: () => onThemeModeChanged(ThemeMode.system),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_suggest,
                      size: 16,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Use system default',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.cardBackground.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.cardBorder.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryEnd),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.cardBackground.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.cardBorder.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryEnd),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox(height: 2);
  }

  void _showConfirmDialog(
    BuildContext context,
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade300
                : Colors.grey.shade700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
