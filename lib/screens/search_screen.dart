import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  bool _userTappedSearch = false; // ISSUE #7: Only show dropdown after user tap

  @override
  void initState() {
    super.initState();
    // Don't auto-request focus - let user tap to show dropdown
    _searchController.addListener(_onSearchChanged);
    // ISSUE #7 FIX: Removed focus listener that auto-showed suggestions
    // Dropdown now only appears after user types or taps the search field
    _fetchAvailableTags();
  }

  Future<void> _fetchAvailableTags() async {
    setState(() {
      // Use the actual current tags passed from gallery (sorted by popularity)
      // FIX #6: Only show tags that exist in the gallery
      _allAvailableTags = List.from(widget.recommendedTags);
      // FIX #1: Don't add "Unscanned" - it's passed from gallery only if unscanned photos exist
      // Filter out already selected tags
      if (widget.excludeTags != null) {
        _allAvailableTags = _allAvailableTags
            .where((tag) => !widget.excludeTags!.contains(tag))
            .toList();
      }
      _loadingTags = false;
    });
    // Show initial suggestions after tags are loaded
    _onSearchChanged();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        // Show top 8 popular suggestions when field is empty but focused
        // Include selected tags at the top, then unselected ones
        final selectedInList = _allAvailableTags
            .where((tag) => _selectedTags.contains(tag))
            .toList();
        final unselectedInList = _allAvailableTags
            .where((tag) {
              if (_selectedTags.contains(tag)) return false;
              if (widget.excludeTags != null &&
                  widget.excludeTags!.contains(tag)) {
                return false;
              }
              return true;
            })
            .take(8 - selectedInList.length)
            .toList();
        _filteredSuggestions = [...selectedInList, ...unselectedInList];
      });
      return;
    }

    setState(() {
      _filteredSuggestions = _allAvailableTags.where((tag) {
        // Filter by search query
        if (!tag.toLowerCase().contains(query)) return false;
        // Don't filter out selected tags - show them with checkmark
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
        // FIX: Prevent keyboard from resizing the layout and shrinking dropdown
        resizeToAvoidBottomInset: false,
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
                          // ISSUE #7: Show dropdown when user taps the field
                          onTap: () {
                            if (!_userTappedSearch) {
                              setState(() {
                                _userTappedSearch = true;
                                _onSearchChanged(); // Show suggestions after tap
                              });
                            }
                          },
                          style: GoogleFonts.poppins(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search photos by tag...',
                            hintStyle: GoogleFonts.poppins(
                              color:
                                  (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black54)
                                      .withValues(alpha: 0.5),
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.lightBlue.shade300,
                            ),
                            suffixIcon: _selectedTags.isNotEmpty
                                // FIX #4: Show orange arrow button when tags are selected
                                ? Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                      ),
                                      onPressed: _performSearch,
                                    ),
                                  )
                                : (_searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          color: Colors.lightBlue.shade300,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                            _onSearchChanged();
                                          });
                                        },
                                      )
                                    : null),
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
              // Show loading indicator while tags are being fetched
              if (_loadingTags)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.lightBlue.shade300,
                      ),
                    ),
                  ),
                )
              // Dropdown suggestions (shows popular when empty, filtered when typing)
              // ISSUE #7 FIX: Only show dropdown after user taps the search field
              else if (_userTappedSearch && _filteredSuggestions.isNotEmpty)
                Flexible(
                  child: Container(
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    // ISSUE #6 FIX: Increased dropdown height to 70% of screen (was 50%)
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header showing context
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Common Words'
                                    : 'Suggestions',
                                style: TextStyle(
                                  color: Colors.lightBlue.shade300,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              // Scroll indicator
                              if (_filteredSuggestions.length > 5)
                                Text(
                                  '${_filteredSuggestions.length} items',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Scrollbar(
                            thumbVisibility: true,
                            thickness: 6,
                            radius: const Radius.circular(3),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(right: 8),
                              itemCount: _filteredSuggestions.length,
                              itemBuilder: (context, index) {
                                final tag = _filteredSuggestions[index];
                                final isAlreadySelected = _selectedTags
                                    .contains(tag);
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isAlreadySelected) {
                                        _selectedTags.remove(tag);
                                      } else {
                                        _selectedTags.add(tag);
                                      }
                                      _searchController.clear();
                                      // Keep dropdown open - just refresh suggestions
                                      _onSearchChanged();
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isAlreadySelected
                                          ? Colors.lightBlue.shade100
                                                .withValues(alpha: 0.3)
                                          : null,
                                      border:
                                          index <
                                              _filteredSuggestions.length - 1
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
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tag,
                                            style: GoogleFonts.poppins(
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 16,
                                              fontWeight: isAlreadySelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        if (isAlreadySelected)
                                          Icon(
                                            Icons.check,
                                            color: Colors.lightBlue.shade400,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_loadingTags && _filteredSuggestions.isNotEmpty)
                const SizedBox(height: 16),
              // Selected tags display (if any)
              if (_selectedTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedTags
                        .map((tag) => _buildTagChip(tag))
                        .toList(),
                  ),
                ),
              // Spacer to push content up
              const Expanded(child: SizedBox()),
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
