import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bitemates/core/services/experience_service.dart';

class WriteReviewSheet extends StatefulWidget {
  final String experienceId;
  final String experienceTitle;
  final VoidCallback? onReviewSubmitted;

  const WriteReviewSheet({
    super.key,
    required this.experienceId,
    required this.experienceTitle,
    this.onReviewSubmitted,
  });

  /// Show this sheet as a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String experienceId,
    required String experienceTitle,
    VoidCallback? onReviewSubmitted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WriteReviewSheet(
        experienceId: experienceId,
        experienceTitle: experienceTitle,
        onReviewSubmitted: onReviewSubmitted,
      ),
    );
  }

  @override
  State<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<WriteReviewSheet> {
  final _experienceService = ExperienceService();
  final _reviewController = TextEditingController();

  int _overallRating = 0;
  int _communicationRating = 0;
  int _valueRating = 0;
  int _organizationRating = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_overallRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an overall rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _experienceService.submitReview(
        experienceId: widget.experienceId,
        rating: _overallRating,
        reviewText: _reviewController.text.trim().isNotEmpty
            ? _reviewController.text.trim()
            : null,
        communicationRating:
            _communicationRating > 0 ? _communicationRating : null,
        valueRating: _valueRating > 0 ? _valueRating : null,
        organizationRating:
            _organizationRating > 0 ? _organizationRating : null,
      );

      widget.onReviewSubmitted?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review submitted! Thank you 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent';
      default:
        return 'Tap to rate';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              'Rate your experience',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.experienceTitle,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 28),

            // Overall Rating (large stars)
            Text(
              'Overall Rating',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStarRow(
                  rating: _overallRating,
                  size: 40,
                  onTap: (i) {
                    HapticFeedback.lightImpact();
                    setState(() => _overallRating = i);
                  },
                ),
                const SizedBox(width: 16),
                Text(
                  _ratingLabel(_overallRating),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _overallRating > 0
                        ? Colors.amber[800]
                        : Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Category Ratings
            _buildCategoryRating(
              label: 'Communication',
              icon: Icons.chat_bubble_outline,
              rating: _communicationRating,
              onTap: (i) {
                HapticFeedback.lightImpact();
                setState(() => _communicationRating = i);
              },
            ),
            const SizedBox(height: 16),
            _buildCategoryRating(
              label: 'Value for Money',
              icon: Icons.payments_outlined,
              rating: _valueRating,
              onTap: (i) {
                HapticFeedback.lightImpact();
                setState(() => _valueRating = i);
              },
            ),
            const SizedBox(height: 16),
            _buildCategoryRating(
              label: 'Organization',
              icon: Icons.event_available_outlined,
              rating: _organizationRating,
              onTap: (i) {
                HapticFeedback.lightImpact();
                setState(() => _organizationRating = i);
              },
            ),
            const SizedBox(height: 28),

            // Written review
            Text(
              'Write a review (optional)',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reviewController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'Share your experience — what did you enjoy? anything to improve?',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.amber, width: 2),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _isSubmitting || _overallRating == 0 ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Submit Review',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRow({
    required int rating,
    required double size,
    required void Function(int) onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap: () => onTap(starIndex),
          child: AnimatedScale(
            scale: rating >= starIndex ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              rating >= starIndex ? Icons.star_rounded : Icons.star_outline_rounded,
              color: rating >= starIndex ? Colors.amber : Colors.grey[300],
              size: size,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCategoryRating({
    required String label,
    required IconData icon,
    required int rating,
    required void Function(int) onTap,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ),
        _buildStarRow(rating: rating, size: 24, onTap: onTap),
      ],
    );
  }
}
