import 'package:flutter/material.dart';
import 'package:bitemates/features/activity/widgets/my_hangouts_list.dart';
import 'package:bitemates/features/activity/widgets/my_tickets_tab.dart';
import 'package:bitemates/features/activity/widgets/discover_tab.dart';

class ActivityScreen extends StatefulWidget {
  final void Function(String tableId)? onHangoutTap;
  const ActivityScreen({super.key, this.onHangoutTap});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          title: Text(
            'Explore',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          bottom: TabBar(
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey[400],
            indicatorColor: Theme.of(context).primaryColor,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Discover'),
              Tab(text: 'My Tickets'),
              Tab(text: 'My Hangouts'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            DiscoverTab(onHangoutTap: widget.onHangoutTap),
            const MyTicketsTab(),
            const MyHangoutsList(),
          ],
        ),
      ),
    );
  }
}
