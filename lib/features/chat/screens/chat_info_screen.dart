import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';
import 'package:bitemates/features/map/widgets/edit_hangout_sheet.dart';
import 'package:bitemates/core/utils/image_url.dart';

class ChatInfoScreen extends StatefulWidget {
  final String title;
  final String chatType;
  final List<Map<String, dynamic>> participants;

  /// Table/hangout id — used to fetch address, date and description.
  final String? tableId;

  const ChatInfoScreen({
    super.key,
    required this.title,
    required this.chatType,
    required this.participants,
    this.tableId,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _loadingDetails = false;
  DateTime? _datetime;
  String? _address;
  String? _description;

  /// The whole hangout row, kept so the host can edit from here without a
  /// second round trip. Null for DM and trip chats, which have no hangout.
  Map<String, dynamic>? _table;

  /// Editing is the host's, and only while the hangout is still open — a
  /// completed or cancelled one is a record, not a plan.
  bool get _canEdit {
    final t = _table;
    if (t == null) return false;
    final me = SupabaseConfig.client.auth.currentUser?.id;
    return me != null && t['host_id'] == me && t['status'] == 'open';
  }

  @override
  void initState() {
    super.initState();
    // Only hangouts (tables) carry address / date / description.
    if (widget.chatType == 'table' && widget.tableId != null) {
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    setState(() => _loadingDetails = true);
    try {
      final row = await SupabaseConfig.client
          .from('tables')
          .select(
            'id, host_id, status, title, description, datetime, '
            'location_name, venue_address, latitude, longitude, max_guests',
          )
          .eq('id', widget.tableId!)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _table = row;
        _datetime = DateTime.tryParse(row?['datetime']?.toString() ?? '');
        final addr = (row?['venue_address'] as String?)?.trim();
        final desc = (row?['description'] as String?)?.trim();
        // Fall back to the venue name. Hangouts created from a suggestion
        // carry no street address, so reading only `venue_address` showed
        // those chats no place at all — the one fact people open this screen
        // for.
        final name = (row?['location_name'] as String?)?.trim();
        _address = (addr != null && addr.isNotEmpty)
            ? addr
            : (name != null && name.isNotEmpty)
            ? name
            : null;
        _description = (desc != null && desc.isNotEmpty) ? desc : null;
        _loadingDetails = false;
      });
    } catch (e) {
      print('❌ ChatInfoScreen: error loading hangout details: $e');
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  /// Opens the host editor on the row already in hand, then reloads so this
  /// screen shows what was saved rather than what it opened with.
  Future<void> _openEditor() async {
    final table = _table;
    if (table == null) return;
    final saved = await EditHangoutSheet.show(context, table: table);
    if (saved && mounted) await _loadDetails();
  }

  bool get _hasDetails =>
      _datetime != null || _address != null || _description != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Info'),
        centerTitle: true,
        actions: [
          // The host's way in from the chat side. Guests see nothing here, so
          // the screen does not advertise a control that would only refuse
          // them.
          if (_canEdit)
            TextButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit'),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Header with big chat title
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(
                      context,
                    ).primaryColor.withOpacity(0.1),
                    child: Icon(
                      widget.chatType == 'table'
                          ? Icons.restaurant
                          : Icons.flight,
                      size: 40,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.participants.length} Participants',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            ),
          ),

          // Hangout details (date / address / description)
          if (_loadingDetails)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            )
          else if (_hasDetails)
            SliverToBoxAdapter(child: _buildDetailsCard(context)),

          // Divider
          const SliverToBoxAdapter(child: Divider(height: 32)),

          // Section label
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PARTICIPANTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),

          // Participants List
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final participant = widget.participants[index];
                final displayName =
                    participant['displayName'] ?? 'Unknown User';
                final photoUrl = participant['photoUrl'];
                final userId = participant['userId'];

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: photoUrl != null
                        ? CachedNetworkImageProvider(ImageUrl.avatar(photoUrl, 48))
                        : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    if (userId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserProfileScreen(userId: userId),
                        ),
                      );
                    }
                  },
                );
              }, childCount: widget.participants.length),
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          if (_datetime != null)
            _detailRow(
              context,
              icon: Icons.calendar_today_rounded,
              label: 'When',
              value: DateFormat('EEE, MMM d · h:mm a').format(_datetime!),
            ),
          if (_datetime != null && (_address != null || _description != null))
            _rowDivider(isDark),
          if (_address != null)
            _detailRow(
              context,
              icon: Icons.location_on_rounded,
              label: 'Where',
              value: _address!,
            ),
          if (_address != null && _description != null) _rowDivider(isDark),
          if (_description != null)
            _detailRow(
              context,
              icon: Icons.notes_rounded,
              label: 'About',
              value: _description!,
            ),

          // Sat directly under the facts it changes: a host notices the wrong
          // time while reading the time, not while looking at the app bar.
          if (_canEdit) ...[
            _rowDivider(isDark),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _openEditor,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Change the place, time or size'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Theme.of(context).primaryColor,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowDivider(bool isDark) => Divider(
        height: 1,
        thickness: 1,
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05),
      );

  Widget _detailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
