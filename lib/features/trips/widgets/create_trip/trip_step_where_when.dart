import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:bitemates/core/theme/app_theme.dart';
import 'create_trip_flow.dart';

/// Step 1: Where are you going? + When?
class TripStepWhereWhen extends StatelessWidget {
  final CreateTripFlowState flow;
  const TripStepWhereWhen({super.key, required this.flow});

  static const String _fallbackGoogleKey =
      'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';

  String get _googleApiKey {
    final envKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    return envKey.isNotEmpty ? envKey : _fallbackGoogleKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero illustration ──
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flight_takeoff_rounded,
                  size: 40,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Where are you headed?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'We\'ll match you with others going to the same place',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: onSurface.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Destination field ──
            Text(
              'Destination',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: GooglePlaceAutoCompleteTextField(
                textEditingController: flow.cityController,
                googleAPIKey: _googleApiKey,
                inputDecoration: InputDecoration(
                  hintText: 'Search for a city...',
                  hintStyle: TextStyle(color: onSurface.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: onSurface.withOpacity(0.4),
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                ),
                debounceTime: 800,
                isLatLngRequired: false,
                getPlaceDetailWithLatLng: (Prediction prediction) {},
                itemClick: (Prediction prediction) {
                  flow.cityController.text = prediction.description ?? '';
                  flow.cityController.selection = TextSelection.fromPosition(
                    TextPosition(offset: flow.cityController.text.length),
                  );
                  final parts = (prediction.description ?? '').split(',');
                  if (parts.length > 1) {
                    flow.countryController.text = parts.last.trim();
                  } else {
                    flow.countryController.text = parts.first.trim();
                  }
                  FocusScope.of(context).unfocus();
                  flow.rebuild();
                },
                itemBuilder: (context, index, Prediction prediction) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.location_city, color: Colors.grey[400]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            prediction.description ?? '',
                            style: TextStyle(color: onSurface),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 28),

            // ── Date range ──
            Text(
              'Travel Dates',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: flow.selectDateRange,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: flow.startDate != null
                      ? Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.3),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            flow.startDate == null || flow.endDate == null
                                ? 'Select dates'
                                : '${DateFormat('MMM d').format(flow.startDate!)} - ${DateFormat('MMM d, yyyy').format(flow.endDate!)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: flow.startDate == null
                                  ? onSurface.withOpacity(0.4)
                                  : onSurface,
                            ),
                          ),
                          if (flow.startDate != null && flow.endDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${flow.endDate!.difference(flow.startDate!).inDays + 1} days',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: onSurface.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
