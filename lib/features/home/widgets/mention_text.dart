import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/features/profile/screens/user_profile_screen.dart';

/// Renders text with @mentions highlighted and tappable.
/// Tapping a mention navigates to the mentioned user's profile.
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? Theme.of(context).textTheme.bodyMedium!;
    final mentionStyle = defaultStyle.copyWith(
      color: Theme.of(context).primaryColor,
      fontWeight: FontWeight.w600,
    );

    // Regex to match @username (alphanumeric + underscores)
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in mentionRegex.allMatches(text)) {
      // Add text before the mention
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      // Add the mention as a tappable span
      final username = match.group(1)!;
      spans.add(TextSpan(
        text: '@$username',
        style: mentionStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _navigateToProfile(context, username),
      ));

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    // If no mentions found, return plain text
    if (spans.isEmpty) {
      return Text(text, style: defaultStyle, maxLines: maxLines, overflow: overflow);
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  void _navigateToProfile(BuildContext context, String username) async {
    try {
      // Look up user by username
      final response = await SupabaseConfig.client
          .from('users')
          .select('id')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      if (response != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: response['id']),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to mentioned user: $e');
    }
  }
}
