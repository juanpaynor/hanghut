import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitemates/core/services/group_service.dart';
import 'package:bitemates/core/services/group_member_service.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';

/// Browse & search public and private groups to join.
class DiscoverGroupsScreen extends StatefulWidget {
  const DiscoverGroupsScreen({super.key});

  @override
  State<DiscoverGroupsScreen> createState() => _DiscoverGroupsScreenState();
}

class _DiscoverGroupsScreenState extends State<DiscoverGroupsScreen> {
  final GroupService _groupService = GroupService();
  final GroupMemberService _memberService = GroupMemberService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _groups = [];
  String _selectedCategory = 'all';
  bool _isLoading = true;

  static const _categoryFilters = <String, Map<String, dynamic>>{
    'all': {'label': 'All', 'icon': Icons.apps},
    'food': {'label': 'Food', 'icon': Icons.restaurant},
    'nightlife': {'label': 'Nightlife', 'icon': Icons.nightlife},
    'travel': {'label': 'Travel', 'icon': Icons.flight},
    'fitness': {'label': 'Fitness', 'icon': Icons.fitness_center},
    'outdoors': {'label': 'Outdoors', 'icon': Icons.terrain},
    'gaming': {'label': 'Gaming', 'icon': Icons.sports_esports},
    'arts': {'label': 'Arts', 'icon': Icons.palette},
    'music': {'label': 'Music', 'icon': Icons.music_note},
    'professional': {'label': 'Pro', 'icon': Icons.work_outline},
    'other': {'label': 'Other', 'icon': Icons.groups},
  };

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      final groups = await _groupService.discoverGroups(
        category:
            _selectedCategory == 'all' ? null : _selectedCategory,
        query: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        limit: 30,
      );
      if (mounted) {
        setState(() {
          _groups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ DISCOVER: Error - $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _quickJoin(Map<String, dynamic> group) async {
    HapticFeedback.mediumImpact();
    final result = await _memberService.joinGroup(group['id']);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Done')),
      );
      // Refresh to update button states
      _loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Groups'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search groups...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadGroups();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).cardTheme.color ??
                    Colors.grey[100],
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _loadGroups(),
              onChanged: (v) => setState(() {}), // Update clear icon
            ),
          ),

          // ── Category Filter Chips
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _categoryFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final entry = _categoryFilters.entries.elementAt(index);
                final isSelected = _selectedCategory == entry.key;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(entry.value['icon'] as IconData,
                          size: 14,
                          color: isSelected ? Colors.white : Colors.teal),
                      const SizedBox(width: 4),
                      Text(entry.value['label'] as String,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: Colors.teal,
                  backgroundColor: Colors.teal.withOpacity(0.06),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (_) {
                    setState(() => _selectedCategory = entry.key);
                    _loadGroups();
                  },
                );
              },
            ),
          ),

          // ── Results List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _groups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No groups found',
                                style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Try a different search or category',
                                style:
                                    TextStyle(color: Colors.grey[400])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadGroups,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _groups.length,
                          itemBuilder: (context, index) =>
                              _buildDiscoverCard(_groups[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverCard(Map<String, dynamic> group) {
    final coverUrl = group['cover_image_url'] as String?;
    final iconEmoji = group['icon_emoji'] as String?;
    final privacy = group['privacy'] as String? ?? 'public';
    final memberCount = group['member_count'] ?? 0;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                GroupDetailScreen(groupId: group['id'] as String),
          ),
        );
        _loadGroups(); // Refresh in case membership changed
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover / Header
            Container(
              height: 100,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                gradient: coverUrl == null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.teal[400]!, Colors.teal[700]!],
                      )
                    : null,
                image: coverUrl != null
                    ? DecorationImage(
                        image: NetworkImage(coverUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: coverUrl == null
                  ? Center(
                      child: iconEmoji != null && iconEmoji.isNotEmpty
                          ? Text(iconEmoji,
                              style: const TextStyle(fontSize: 36))
                          : Icon(Icons.groups,
                              size: 36,
                              color: Colors.white.withOpacity(0.4)),
                    )
                  : null,
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'] ?? 'Group',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.people_outline,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text('$memberCount members',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500])),
                            const SizedBox(width: 8),
                            Icon(
                              privacy == 'public'
                                  ? Icons.public
                                  : Icons.lock_outline,
                              size: 13,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              privacy[0].toUpperCase() +
                                  privacy.substring(1),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                        if (group['description'] != null &&
                            (group['description'] as String).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            group['description'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Quick Join Button
                  ElevatedButton(
                    onPressed: () => _quickJoin(group),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    child: Text(
                        privacy == 'private' ? 'Request' : 'Join'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
