import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitemates/core/config/supabase_config.dart';

class CoachMarkService {
  // Bump this to re-show the tour to everyone (even users who already saw it).
  static const seenKey = 'onboarding_coach_marks_v5';

  /// Built-in tour. Used as a guaranteed fallback when the remote table is
  /// empty/unreachable (network, RLS, etc.) so the tour ALWAYS shows on a fresh
  /// install instead of silently doing nothing.
  static const List<Map<String, dynamic>> _defaultSteps = [
    {
      'step_order': 1,
      'target_key': 'nav_map',
      'title': 'Explore Your City',
      'body':
          'Discover hangouts, events, and experiences happening near you right now.',
    },
    {
      'step_order': 2,
      'target_key': 'nav_feed',
      'title': 'Your Social Feed',
      'body': 'See stories, posts, and moments from people around you.',
    },
    {
      'step_order': 3,
      'target_key': 'fab',
      'title': 'Create & Share',
      'body':
          'Start a hangout, share a story, or write a post for your community.',
    },
    {
      'step_order': 4,
      'target_key': 'nav_explore',
      'title': 'Tickets & Experiences',
      'body': 'Find events, buy tickets, and book unique local experiences.',
    },
    {
      'step_order': 5,
      'target_key': 'nav_profile',
      'title': 'Your Profile',
      'body': 'Set up your profile so others can find and connect with you.',
    },
  ];

  Future<bool> shouldShowOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(seenKey) ?? false);
  }

  Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(seenKey, true);
  }

  /// Returns the active coach marks from the server, or the built-in defaults
  /// if the remote table is empty or the fetch fails. Never returns empty when
  /// defaults exist, so the tour can always render.
  Future<List<Map<String, dynamic>>> fetchOnboardingSteps() async {
    try {
      final response = await SupabaseConfig.client
          .from('coach_marks')
          .select('step_order, target_key, title, body')
          .eq('is_active', true)
          .order('step_order');
      final rows = List<Map<String, dynamic>>.from(response as List);
      if (rows.isNotEmpty) return rows;
      print('ℹ️ coach_marks remote empty — using built-in defaults');
      return _defaultSteps;
    } catch (e) {
      print('⚠️ Could not fetch coach marks ($e) — using built-in defaults');
      return _defaultSteps;
    }
  }
}
