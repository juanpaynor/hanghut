import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Result returned when a place is selected.
class PlaceResult {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const PlaceResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// A bottom-sheet Google Places autocomplete searcher.
/// Usage:
///   final result = await PlaceSearchSheet.show(context, currentLat: ..., currentLng: ...);
///   if (result != null) { ... }
class PlaceSearchSheet extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;

  const PlaceSearchSheet({super.key, this.currentLat, this.currentLng});

  static Future<PlaceResult?> show(
    BuildContext context, {
    double? currentLat,
    double? currentLng,
  }) {
    return showModalBottomSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          PlaceSearchSheet(currentLat: currentLat, currentLng: currentLng),
    );
  }

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _isLoading = false;

  static const String _fallbackKey = 'AIzaSyDOIku975W5J2mTaCwqgahOQcbRhw-iRaA';
  String get _apiKey {
    final k = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
    return k.isNotEmpty ? k : _fallbackKey;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Auto-focus after sheet animates in
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String input) async {
    setState(() => _isLoading = true);
    try {
      var url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$_apiKey';
      if (widget.currentLat != null && widget.currentLng != null) {
        url +=
            '&location=${widget.currentLat},${widget.currentLng}&radius=30000';
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'OK') {
          setState(() {
            _predictions = List<Map<String, dynamic>>.from(
              (data['predictions'] as List).map(
                (p) => {
                  'place_id': p['place_id'],
                  'main_text': p['structured_formatting']['main_text'],
                  'secondary_text':
                      p['structured_formatting']['secondary_text'] ?? '',
                },
              ),
            );
          });
        } else {
          setState(() => _predictions = []);
        }
      }
    } catch (e) {
      debugPrint('PlaceSearchSheet: search error $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> prediction) async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=${prediction['place_id']}&key=$_apiKey&fields=geometry,name,formatted_address',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final loc = result['geometry']['location'];
          if (mounted) {
            Navigator.pop(
              context,
              PlaceResult(
                name: result['name'] as String? ?? prediction['main_text'],
                address:
                    result['formatted_address'] as String? ??
                    prediction['secondary_text'],
                latitude: (loc['lat'] as num).toDouble(),
                longitude: (loc['lng'] as num).toDouble(),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('PlaceSearchSheet: details error $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Search bar
          TextField(
            controller: _controller,
            focusNode: _focus,
            decoration: InputDecoration(
              hintText: 'Search for a place...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _predictions = []);
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_predictions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 8),
                itemCount: _predictions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) {
                  final p = _predictions[i];
                  return ListTile(
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: Colors.grey,
                    ),
                    title: Text(
                      p['main_text'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      p['secondary_text'] as String,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    onTap: () => _selectPlace(p),
                  );
                },
              ),
            ),
          if (_predictions.isEmpty && _controller.text.isEmpty) ...[
            const SizedBox(height: 24),
            Icon(Icons.place_outlined, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              'Type to search for a venue or place',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
