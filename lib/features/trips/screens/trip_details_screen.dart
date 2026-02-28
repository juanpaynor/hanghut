import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/services/trip_service.dart';
import 'package:bitemates/features/chat/screens/chat_screen.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/trips/screens/trip_matches_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final _tripService = TripService();
  List<Map<String, dynamic>> _matches = [];
  bool _isLoadingMatches = true;
  bool _isJoiningChat = false;

  Map<String, dynamic>? _ownerProfile;
  // ignore: unused_field
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
    _loadMatches();
  }

  Future<void> _loadOwnerProfile() async {
    try {
      final ownerId = widget.trip['user_id'];
      if (ownerId != null) {
        final profile = await SupabaseConfig.client
            .from('users')
            .select('display_name, avatar_url, bio, user_photos(photo_url)')
            .eq('id', ownerId)
            .maybeSingle();

        print('Profile loaded: $profile'); // Debug print
        if (mounted) {
          setState(() {
            _ownerProfile = profile;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading owner profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _getAvatarUrl() {
    if (_ownerProfile == null) return null;

    final photos = _ownerProfile!['user_photos'] as List?;
    if (photos != null && photos.isNotEmpty) {
      // Find primary or first
      // Assuming sorting or primary flag, but for now take first
      return photos[0]['photo_url']?.toString();
    }

    final avatar = _ownerProfile!['avatar_url']?.toString();
    if (avatar != null && avatar.isNotEmpty) return avatar;

    return null;
  }

  Future<void> _loadMatches() async {
    final matches = await _tripService.getTripMatches(widget.trip['id']);
    if (mounted) {
      setState(() {
        _matches = matches;
        _isLoadingMatches = false;
      });
    }
  }

  Future<void> _joinGroupChat() async {
    setState(() => _isJoiningChat = true);
    final chatInfo = await _tripService.joinTripGroupChat(widget.trip['id']);

    if (mounted && chatInfo != null) {
      setState(() {
        _isJoiningChat = false;
      });

      // Navigate to Chat
      // Deriving a title like "Tokyo Chat"
      final title = '${widget.trip['destination_city']} Travelers';

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (context) => ChatScreen(
          tableId: chatInfo['chatId'], // Actual Trip Chat UUID
          tableTitle: title,
          channelId: chatInfo['channelId'], // Ably Channel ID
          chatType: 'trip',
        ),
      );
    } else {
      if (mounted) setState(() => _isJoiningChat = false);
    }
  }

  Future<void> _deleteTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip?'),
        content: const Text(
          'Are you sure you want to delete this trip? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _tripService.deleteTrip(widget.trip['id']);
      if (success && mounted) {
        Navigator.pop(context); // Return to previous screen
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete trip')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDate = DateTime.parse(widget.trip['start_date']);
    final endDate = DateTime.parse(widget.trip['end_date']);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${widget.trip['destination_city']} Trip'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (widget.trip['user_id'] ==
              SupabaseConfig.client.auth.currentUser?.id)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteTrip,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header with Destination Info
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black,
                image: const DecorationImage(
                  image: NetworkImage(
                    'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?q=80&w=2574&auto=format&fit=crop',
                  ), // Placeholder or dynamic city image
                  fit: BoxFit.cover,
                  opacity: 0.6,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.trip['destination_city'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.trip['destination_country'],
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFFC107,
                        ), // AppTheme Accent (Yellow)
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        DateFormat('MMM d').format(startDate) +
                            ' - ' +
                            DateFormat('MMM d, yyyy').format(endDate),
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 1.5. Traveler Info (Public View)
            if (_ownerProfile != null)
              GestureDetector(
                onTap: () {
                  if (widget.trip['user_id'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UserProfileScreen(userId: widget.trip['user_id']),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: _getAvatarUrl() != null
                            ? NetworkImage(_getAvatarUrl()!)
                            : null,
                        backgroundColor: Colors.grey[200],
                        child: _getAvatarUrl() == null
                            ? Text(
                                (_ownerProfile!['display_name'] ?? 'U')[0]
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip by ${_ownerProfile!['display_name'] ?? 'Traveler'}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_ownerProfile!['bio'] != null)
                            Text(
                              _ownerProfile!['bio'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // 2. Action Buttons (Chat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isJoiningChat ? null : _joinGroupChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isJoiningChat
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline),
                  label: Text(
                    _isJoiningChat
                        ? 'Connecting...'
                        : 'Join ${widget.trip['destination_city']} Group Chat',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 3. Travelers (Matches)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          TripMatchesScreen(trip: widget.trip),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    const Text(
                      'Also in Town',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const Spacer(),
                    if (_matches.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_matches.length} matches',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_isLoadingMatches)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_matches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No other travelers found yet.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      Text(
                        "Be the first to say hi in the chat!",
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 140,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  scrollDirection: Axis.horizontal,
                  itemCount: _matches.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final match = _matches[index];
                    return Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundImage: match['avatar_url'] != null
                              ? NetworkImage(match['avatar_url'])
                              : null,
                          backgroundColor: Colors.grey[200],
                          child: match['avatar_url'] == null
                              ? const Icon(
                                  Icons.person,
                                  size: 36,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          match['display_name'] ?? 'User',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${match['overlap_days']} days overlap',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
