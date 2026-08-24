import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bitemates/core/services/places_service.dart';

/// A drop-in autocomplete text field backed by [PlacesService] (Places API New).
///
/// Replaces the deprecated `google_places_flutter` package's
/// `GooglePlaceAutoCompleteTextField`. Renders an inline predictions list under
/// the field and calls [onSelected] with the chosen prediction.
class PlacesAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration? decoration;
  final void Function(PlacePrediction prediction) onSelected;
  final int debounceMs;
  final double? lat;
  final double? lng;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    required this.onSelected,
    this.decoration,
    this.debounceMs = 800,
    this.lat,
    this.lng,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  Timer? _debounce;
  List<PlacePrediction> _predictions = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(
      Duration(milliseconds: widget.debounceMs),
      () => _search(value),
    );
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await PlacesService.instance.autocomplete(
      query,
      lat: widget.lat,
      lng: widget.lng,
    );
    if (!mounted) return;
    setState(() {
      _predictions = results;
      _loading = false;
    });
  }

  void _select(PlacePrediction prediction) {
    setState(() => _predictions = []);
    widget.onSelected(prediction);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: (widget.decoration ?? const InputDecoration()).copyWith(
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.decoration?.suffixIcon,
          ),
        ),
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onSurface.withOpacity(0.08)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return InkWell(
                  onTap: () => _select(p),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_city,
                          color: onSurface.withOpacity(0.4),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.description.isNotEmpty ? p.description : p.mainText,
                            style: TextStyle(color: onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
