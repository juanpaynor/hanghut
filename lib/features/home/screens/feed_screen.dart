import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/map/widgets/table_details_bottom_sheet.dart';
import 'package:intl/intl.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _tables = [];
  bool _isLoading = true;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadTables();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    setState(() => _isLoading = true);
    try {
      final tables = await SupabaseConfig.client
          .from('tables')
          .select('''
            *
          ''')
          .gte('datetime', DateTime.now().toIso8601String())
          .order('datetime', ascending: true)
          .limit(20);

      // Fetch host data separately for each table
      final enrichedTables = await Future.wait(
        tables.map((table) async {
          try {
            final hostData = await SupabaseConfig.client
                .from('users')
                .select('display_name, trust_score')
                .eq('id', table['host_id'])
                .maybeSingle();

            return {...table, 'users': hostData};
          } catch (e) {
            print('Error loading host for table ${table['id']}: $e');
            return {
              ...table,
              'users': {'display_name': 'Unknown', 'trust_score': 0},
            };
          }
        }).toList(),
      );

      if (mounted) {
        setState(() {
          _tables = enrichedTables;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading feed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFF16213E),
              const Color(0xFF0F3460),
            ],
            stops: [0.0, 0.5 + (_scrollOffset / 1000).clamp(-0.2, 0.2), 1.0],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? _buildLoadingState()
              : RefreshIndicator(
                  onRefresh: _loadTables,
                  color: const Color(0xFF00FF00),
                  backgroundColor: Colors.white,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      _buildHeader(),
                      _buildFeaturedSection(),
                      _buildMainFeed(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF00FF00),
                      Color(0xFF00FF00).withOpacity(0.3),
                    ],
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              )
              .animate(onPlay: (controller) => controller.repeat())
              .scale(
                duration: 1500.ms,
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.2, 1.2),
              )
              .then()
              .scale(
                duration: 1500.ms,
                begin: const Offset(1.2, 1.2),
                end: const Offset(0.8, 0.8),
              ),
          const SizedBox(height: 24),
          Text(
                'Finding tables...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              )
              .animate(onPlay: (controller) => controller.repeat())
              .fadeIn(duration: 800.ms)
              .then()
              .fadeOut(duration: 800.ms),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                      'Discover',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                    .slideX(begin: -0.3, end: 0),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                  'Tables happening around you',
                  style: TextStyle(
                    color: const Color(0xFF00FF00),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                )
                .animate()
                .fadeIn(delay: 200.ms, duration: 600.ms)
                .slideX(begin: -0.3, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedSection() {
    if (_tables.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

    final featured = _tables.take(3).toList();

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: featured.length,
          itemBuilder: (context, index) {
            return _buildFeaturedCard(featured[index], index);
          },
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> table, int index) {
    final markerUrl = table['marker_image_url'];
    final hostName = table['users']?['display_name'] ?? 'Unknown';
    final datetime = DateTime.parse(table['datetime']);
    final timeUntil = datetime.difference(DateTime.now());

    return GestureDetector(
      onTap: () => _showTableDetails(table),
      child:
          Container(
                width: 300,
                margin: const EdgeInsets.only(right: 16, bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF00FF00).withOpacity(0.2),
                      Color(0xFF00FF00).withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: Color(0xFF00FF00).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // Background Pattern
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CirclePatternPainter(
                          color: Colors.white.withOpacity(0.03),
                          offset: _scrollOffset * (index + 1) * 0.1,
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Marker Image
                          if (markerUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                markerUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Color(0xFF00FF00),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.restaurant,
                                color: Colors.black,
                              ),
                            ),
                          // Title
                          Text(
                            table['title'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Time & Host
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    color: Color(0xFF00FF00),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTimeUntil(timeUntil),
                                    style: TextStyle(
                                      color: Color(0xFF00FF00),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Hosted by $hostName',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(delay: (300 + index * 100).ms, duration: 600.ms)
              .slideX(begin: 0.3, end: 0, curve: Curves.easeOutBack)
              .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
    );
  }

  Widget _buildMainFeed() {
    if (_tables.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0xFF00FF00).withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.restaurant_menu,
                      size: 64,
                      color: Color(0xFF00FF00).withOpacity(0.5),
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .rotate(duration: 4000.ms, begin: 0, end: 1),
              const SizedBox(height: 24),
              Text(
                'No tables yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Be the first to host!',
                style: TextStyle(color: Colors.white60, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index < 3) return const SizedBox();
          return _buildTableCard(_tables[index], index);
        }, childCount: _tables.length),
      ),
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table, int index) {
    final markerUrl = table['marker_image_url'];
    final hostName = table['users']?['display_name'] ?? 'Unknown';
    final datetime = DateTime.parse(table['datetime']);
    final locationName = table['location_name'] ?? 'Unknown location';

    return GestureDetector(
      onTap: () => _showTableDetails(table),
      child:
          Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.white.withOpacity(0.05),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      // Background with parallax effect
                      if (markerUrl != null)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(0, _scrollOffset * 0.05),
                            child: Image.network(
                              markerUrl,
                              fit: BoxFit.cover,
                              color: Colors.black.withOpacity(0.7),
                              colorBlendMode: BlendMode.darken,
                            ),
                          ),
                        ),

                      // Gradient overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.8),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Content
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Host info
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF00FF00),
                                        Color(0xFF00FF00).withOpacity(0.6),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      hostName[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      hostName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Host',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 80),
                            // Title
                            Text(
                              table['title'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Location
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: Color(0xFF00FF00),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    locationName,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Date/Time
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Color(0xFF00FF00),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat(
                                    'EEEE, MMM d · h:mm a',
                                  ).format(datetime),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: (index * 50).ms, duration: 600.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
              .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOut),
    );
  }

  String _formatTimeUntil(Duration duration) {
    if (duration.inMinutes < 60) {
      return 'in ${duration.inMinutes}m';
    } else if (duration.inHours < 24) {
      return 'in ${duration.inHours}h';
    } else {
      return 'in ${duration.inDays}d';
    }
  }

  void _showTableDetails(Map<String, dynamic> table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TableDetailsBottomSheet(
        table: table,
        matchData: null, // No matching data in feed view
      ),
    );
  }
}

class _CirclePatternPainter extends CustomPainter {
  final Color color;
  final double offset;

  _CirclePatternPainter({required this.color, this.offset = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final radius = (size.width / 5) * (i + 1) + (offset % 100);
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_CirclePatternPainter oldDelegate) =>
      oldDelegate.offset != offset;
}
