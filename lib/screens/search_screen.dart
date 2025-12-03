import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SearchScreen extends StatefulWidget {
  final List<String>
  recommendedTags; // Kept for backwards compatibility but not used
  final Function(String) onTagSelected;
  final Set<String>? excludeTags; // Tags to exclude from suggestions

  const SearchScreen({
    super.key,
    required this.recommendedTags,
    required this.onTagSelected,
    this.excludeTags,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _selectedTags = {};
  List<String> _filteredSuggestions = [];
  List<String> _allAvailableTags = []; // Tags fetched from server
  bool _loadingTags = true;

  @override
  void initState() {
    super.initState();
    _searchFocus.requestFocus();
    _searchController.addListener(_onSearchChanged);
    _fetchAvailableTags();
  }

  Future<void> _fetchAvailableTags() async {
    setState(() {
      // Use the actual current tags passed from gallery instead of server
      _allAvailableTags = List.from(widget.recommendedTags);
      // Add "None" for searching untagged photos if not already present
      if (!_allAvailableTags.contains('None')) {
        _allAvailableTags.insert(0, 'None');
      }
      // Filter out already selected tags
      if (widget.excludeTags != null) {
        _allAvailableTags = _allAvailableTags
            .where((tag) => !widget.excludeTags!.contains(tag))
            .toList();
      }
      _loadingTags = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredSuggestions = [];
      });
      return;
    }

    setState(() {
      _filteredSuggestions = _allAvailableTags.where((tag) {
        // Filter by search query
        if (!tag.toLowerCase().contains(query)) return false;
        // Filter out already selected tags
        if (widget.excludeTags != null && widget.excludeTags!.contains(tag)) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _performSearch() {
    if (_selectedTags.isNotEmpty) {
      final searchQuery = _selectedTags.join(' ');
      widget.onTagSelected(searchQuery);
      Navigator.pop(context);
    } else if (_searchController.text.isNotEmpty) {
      widget.onTagSelected(_searchController.text);
      Navigator.pop(context);
    }
  }

  Widget _buildTagChip(String tag) {
    final isSelected = _selectedTags.contains(tag);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedTags.remove(tag);
          } else {
            _selectedTags.add(tag);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    Colors.lightBlue.shade400,
                    Colors.lightBlue.shade600,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected
              ? null
              : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          tag,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade300,
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade900
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.lightBlue.shade300.withValues(
                              alpha: 0.3,
                            ),
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search photos by tag...',
                            hintStyle: TextStyle(
                              color:
                                  (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black54)
                                      .withValues(alpha: 0.5),
                              fontSize: 16,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.lightBlue.shade300,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (value) {
                            _performSearch();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Dropdown suggestions
              if (_filteredSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.lightBlue.shade300.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _filteredSuggestions.length,
                    itemBuilder: (context, index) {
                      final tag = _filteredSuggestions[index];
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedTags.add(tag);
                            _searchController.clear();
                            _filteredSuggestions = [];
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: index < _filteredSuggestions.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      width: 1,
                                    ),
                                  )
                                : null,
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_filteredSuggestions.isNotEmpty) const SizedBox(height: 16),
              // Recommended tags section
              Expanded(
                child: _loadingTags
                    ? const Center(child: CircularProgressIndicator())
                    : _allAvailableTags.isEmpty
                    ? Center(
                        child: Text(
                          'No tags available yet.\nUpload and scan some photos!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : Colors.black54,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Tags',
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedTags.isEmpty
                                  ? 'Tap tags to select (${_allAvailableTags.length} available)'
                                  : '${_selectedTags.length} tag${_selectedTags.length == 1 ? '' : 's'} selected',
                              style: TextStyle(
                                color: _selectedTags.isEmpty
                                    ? (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : Colors.black54)
                                          .withValues(alpha: 0.6)
                                    : Colors.lightBlue.shade300,
                                fontSize: 14,
                                fontWeight: _selectedTags.isEmpty
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _allAvailableTags
                                  .map((tag) => _buildTagChip(tag))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
              ),
              // Search button
              if (_selectedTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _performSearch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightBlue.shade500,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            'Search ${_selectedTags.length} tag${_selectedTags.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
