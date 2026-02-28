import 'package:flutter/material.dart';
import 'package:bitemates/features/ticketing/screens/my_tickets_screen.dart';
import 'package:bitemates/features/activity/widgets/my_trips_list.dart';
import 'package:bitemates/features/activity/widgets/my_hangouts_list.dart';
import 'package:bitemates/features/activity/widgets/my_experiences_list.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          title: Text(
            'Activity',
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
              Tab(text: 'Tickets'),
              Tab(text: 'Hangouts'),
              Tab(text: 'Experiences'),
              Tab(text: 'Trips'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            MyTicketsScreen(),
            MyHangoutsList(),
            MyExperiencesList(),
            MyTripsList(),
          ],
        ),
      ),
    );
  }
}
