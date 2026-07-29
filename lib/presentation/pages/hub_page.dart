import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/platform_model.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/platform_card.dart';
import '../widgets/search_bar.dart' as custom_search;

class HubPage extends StatefulWidget {
  final void Function(PlatformModel platform)? onPlatformTap;

  const HubPage({
    super.key,
    this.onPlatformTap,
  });

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  final List<String> _categories = ['All', 'Video', 'Music', 'Education', 'Social', 'Streaming'];
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  List<PlatformModel> get _filteredPlatforms {
    List<PlatformModel> platforms = PlatformConstants.platforms;

    // Apply category filter
    if (_selectedCategory != 'All') {
      platforms = platforms
          .where((p) => p.category == _selectedCategory.toLowerCase())
          .toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      platforms = platforms
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
    }

    return platforms;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onPlatformTap(PlatformModel platform) {
    if (widget.onPlatformTap != null) {
      widget.onPlatformTap!(platform);
    }
  }

  void _onSettingsTap() {
    Navigator.pushNamed(context, '/settings');
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _isSearching = value.isNotEmpty;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.hubGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              CustomAppBar(
                onSettingsTap: _onSettingsTap,
              ),
              const SizedBox(height: 8),

              // Search Bar
              custom_search.SearchBarWidget(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
                showClear: _isSearching,
                onSubmitted: (query) {
                  if (query.isNotEmpty) {
                    setState(() {
                      _searchQuery = query;
                      _isSearching = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 20),

              // Only show category chips when not searching
              if (!_isSearching)
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = category == _selectedCategory;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primaryStart
                                  : Colors.white,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Search results count or spacing
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredPlatforms.length} results for "$_searchQuery"',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _clearSearch,
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 16),

              // Platform grid
              Expanded(
                child: _filteredPlatforms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No platforms found',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: AppConstants.platformGridCrossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _filteredPlatforms.length,
                        itemBuilder: (context, index) {
                          final platform = _filteredPlatforms[index];
                          return PlatformCard(
                            platform: platform,
                            onTap: () => _onPlatformTap(platform),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
