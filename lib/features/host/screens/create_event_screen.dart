import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/places_service.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bitemates/core/services/host_service.dart';
import 'package:bitemates/core/services/event_category_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/utils/error_handler.dart';
import 'package:bitemates/features/home/widgets/location_picker_modal.dart';

/// Host-side create / edit flow for ticketed EVENTS. Writes through the shared
/// web/app RPCs create_event / update_event / manage_tiers (team_comms thread
/// 198). Publishing is handled separately via set_event_published (dashboard
/// toggle) so this screen stays scoped to details + tiers, matching the
/// update_event contract.
class CreateEventScreen extends StatefulWidget {
  final String partnerId;
  final Map<String, dynamic>? existingEvent;

  const CreateEventScreen({
    super.key,
    required this.partnerId,
    this.existingEvent,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _hostService = HostService();
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingEvent != null;
  static const int _totalSteps = 5;

  // Step 1 — Basics
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String? _categoryKey; // event_categories key (snake_case) or null
  String _eventType = 'other'; // events.event_type enum
  List<EventCategoryItem> _categories = [];
  bool _loadingCategories = true;

  // events.event_type enum values (team_comms #204)
  static const _eventTypes = <(String, String, String)>[
    ('concert', '🎤', 'Concert'),
    ('workshop', '🛠️', 'Workshop'),
    ('conference', '🎙️', 'Conference'),
    ('sports', '⚽', 'Sports'),
    ('social', '🥂', 'Social'),
    ('food', '🍽️', 'Food'),
    ('nightlife', '🌙', 'Nightlife'),
    ('art', '🎨', 'Art'),
    ('other', '📌', 'Other'),
  ];

  // Step 2 — Media
  File? _coverFile;
  String? _coverUrl; // existing cover (edit)
  final List<File> _galleryFiles = [];
  final List<String> _galleryUrls = []; // existing gallery (edit)

  // Step 3 — When & Where
  DateTime? _startDateTime;
  DateTime? _endDateTime;
  final _venueController = TextEditingController();
  final _addressController = TextEditingController();
  double _lat = 14.5995;
  double _lng = 120.9842;

  // Google Places
  List<Map<String, dynamic>> _placePredictions = [];
  Timer? _debounce;
  bool _showPredictions = false;
  // Step 4 — Tickets
  final _capacityController = TextEditingController();
  final List<_TierDraft> _tiers = [];
  final Set<String> _originalTierIds = {};
  DateTime? _salesEndDateTime; // sales cutoff; defaults to start−1h server-side
  int _minPerOrder = 1;
  int _maxPerOrder = 10;

  // Registration options (plain toggles per team_comms #210 — copy edited on web)
  bool _requireApproval = false;
  bool _hideVenueUntilRegistered = false;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_onSearchChanged);
    _loadCategories();

    if (_isEditing) {
      _hydrateFromExisting();
    } else {
      // Start with a single General Admission tier so the simplest event is
      // one price + one quantity.
      _tiers.add(_TierDraft(name: 'General Admission'));
    }
  }

  void _hydrateFromExisting() {
    final e = widget.existingEvent!;
    _titleController.text = e['title'] ?? '';
    _descController.text = e['description'] ?? '';
    _categoryKey = e['category'];
    _eventType = e['event_type'] ?? 'other';
    _coverUrl = e['cover_image_url'];
    final imgs = e['images'];
    if (imgs is List) _galleryUrls.addAll(imgs.map((x) => x.toString()));

    _startDateTime = DateTime.tryParse(e['start_datetime'] ?? '')?.toLocal();
    final end = e['end_datetime'];
    if (end != null) _endDateTime = DateTime.tryParse(end)?.toLocal();
    _venueController.text = e['venue_name'] ?? '';
    _addressController.text = e['address'] ?? '';
    _lat = (e['latitude'] as num?)?.toDouble() ?? _lat;
    _lng = (e['longitude'] as num?)?.toDouble() ?? _lng;
    _capacityController.text = (e['capacity'] ?? '').toString();

    final salesEnd = e['sales_end_datetime'];
    if (salesEnd != null) {
      _salesEndDateTime = DateTime.tryParse(salesEnd)?.toLocal();
    }
    _minPerOrder = (e['min_tickets_per_purchase'] as num?)?.toInt() ?? 1;
    _maxPerOrder = (e['max_tickets_per_purchase'] as num?)?.toInt() ?? 10;
    _requireApproval = e['require_approval'] == true;
    _hideVenueUntilRegistered = e['hide_venue_until_registered'] == true;

    final tiers = e['ticket_tiers'];
    if (tiers is List && tiers.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(tiers)
        ..sort((a, b) =>
            ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0)));
      for (final t in sorted) {
        _originalTierIds.add(t['id'] as String);
        _tiers.add(_TierDraft(
          id: t['id'] as String,
          name: t['name'] ?? '',
          price: (t['price'] ?? '').toString(),
          qty: (t['quantity_total'] ?? '').toString(),
          soldQty: (t['quantity_sold'] as num?)?.toInt() ?? 0,
        ));
      }
    } else {
      _tiers.add(_TierDraft(name: 'General Admission'));
    }
  }

  Future<void> _loadCategories() async {
    final cats = await EventCategoryService().getCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
        _loadingCategories = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _venueController.dispose();
    _addressController.dispose();
    _capacityController.dispose();
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────
  void _nextStep() {
    final err = _validateStep(_currentStep);
    if (err != null) {
      _toast(err);
      return;
    }
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Returns an error string if the step is incomplete, else null.
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_titleController.text.trim().isEmpty) return 'Add a title';
        return null;
      case 2:
        if (_startDateTime == null) return 'Pick a start date & time';
        if (_endDateTime != null && _endDateTime!.isBefore(_startDateTime!)) {
          return 'End time must be after the start time';
        }
        if (_venueController.text.trim().isEmpty &&
            _addressController.text.trim().isEmpty) {
          return 'Add a venue or address';
        }
        return null;
      case 3:
        final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;
        if (capacity <= 0) return 'Set a capacity greater than 0';
        for (final t in _activeTiers) {
          if ((int.tryParse(t.qtyCtrl.text) ?? 0) <= 0) {
            return 'Each ticket type needs a quantity';
          }
          final sold = t.soldQty;
          if ((int.tryParse(t.qtyCtrl.text) ?? 0) < sold) {
            return '"${t.nameCtrl.text}" can\'t drop below $sold already sold';
          }
        }
        if (_tierQtySum > capacity) {
          return 'Ticket quantities ($_tierQtySum) exceed capacity ($capacity)';
        }
        // Per-order limits (DB CHECK: min>=1, max<=capacity, max>=min)
        if (_minPerOrder < 1) return 'Min tickets per order must be at least 1';
        if (_maxPerOrder < _minPerOrder) {
          return 'Max per order can\'t be less than the minimum';
        }
        if (_maxPerOrder > capacity) {
          return 'Max per order ($_maxPerOrder) can\'t exceed capacity ($capacity)';
        }
        // Convention: sales must end on or before the event starts (#210 3e)
        if (_salesEndDateTime != null &&
            _startDateTime != null &&
            _salesEndDateTime!.isAfter(_startDateTime!)) {
          return 'Ticket sales must end on or before the event starts';
        }
        return null;
      default:
        return null;
    }
  }

  List<_TierDraft> get _activeTiers =>
      _tiers.where((t) => t.nameCtrl.text.trim().isNotEmpty).toList();

  int get _tierQtySum => _activeTiers.fold(
      0, (sum, t) => sum + (int.tryParse(t.qtyCtrl.text) ?? 0));

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Submit ──────────────────────────────────────────────────────────────
  Future<void> _submit({required bool publish}) async {
    // Run all step validations before an expensive upload.
    for (var s = 0; s < _totalSteps; s++) {
      final err = _validateStep(s);
      if (err != null) {
        _toast(err);
        setState(() => _currentStep = s);
        _pageController.jumpToPage(s);
        return;
      }
    }
    if (_coverFile == null && (_coverUrl == null || _coverUrl!.isEmpty)) {
      _toast('Add a cover image');
      setState(() => _currentStep = 1);
      _pageController.jumpToPage(1);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. Upload media under the partner-owned storage prefix.
      String? coverUrl = _coverUrl;
      if (_coverFile != null) {
        final up = await _hostService.uploadEventMedia(
          partnerId: widget.partnerId,
          bucket: 'event-covers',
          files: [_coverFile!],
        );
        coverUrl = up.first;
      }
      final newGallery = _galleryFiles.isEmpty
          ? <String>[]
          : await _hostService.uploadEventMedia(
              partnerId: widget.partnerId,
              bucket: 'event-images',
              files: _galleryFiles,
            );
      final allGallery = [..._galleryUrls, ...newGallery];

      final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;
      final active = _activeTiers;
      final tiersPayload = <Map<String, dynamic>>[
        for (var i = 0; i < active.length; i++)
          {
            'name': active[i].nameCtrl.text.trim(),
            'price': double.tryParse(active[i].priceCtrl.text) ?? 0,
            'quantity_total': int.tryParse(active[i].qtyCtrl.text) ?? 0,
            'sort_order': i,
          },
      ];
      final basePrice = tiersPayload.isEmpty
          ? 0.0
          : tiersPayload
              .map((t) => t['price'] as double)
              .reduce((a, b) => a < b ? a : b);

      final details = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'category': _categoryKey,
        'event_type': _eventType,
        'seating_type': 'general_admission',
        'venue_name': _venueController.text.trim(),
        'address': _addressController.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        'start_datetime': _startDateTime!.toUtc().toIso8601String(),
        'end_datetime': _endDateTime?.toUtc().toIso8601String(),
        'capacity': capacity,
        'ticket_price': basePrice,
        'cover_image_url': coverUrl,
        'images': allGallery,
        'min_tickets_per_purchase': _minPerOrder,
        'max_tickets_per_purchase': _maxPerOrder,
        'require_approval': _requireApproval,
        'hide_venue_until_registered': _hideVenueUntilRegistered,
        // Omit sales_end when unset: create defaults it to start−1h; update
        // leaves the column unchanged (COALESCE) rather than nulling it.
        if (_salesEndDateTime != null)
          'sales_end_datetime': _salesEndDateTime!.toUtc().toIso8601String(),
      };

      if (_isEditing) {
        final eventId = widget.existingEvent!['id'] as String;
        await _hostService.updateEvent({'event_id': eventId, ...details});
        await _applyTierDiff(eventId);
      } else {
        await _hostService.createEvent({
          'organizer_id': widget.partnerId,
          'status': publish ? 'published' : 'draft',
          'tiers': tiersPayload,
          ...details,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Event updated'
                : publish
                    ? '🎉 Event published!'
                    : 'Draft saved'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context,
            error: e, fallbackMessage: 'Unable to save event. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Diffs the current tier drafts against the originals and calls manage_tiers.
  Future<void> _applyTierDiff(String eventId) async {
    final add = <Map<String, dynamic>>[];
    final update = <Map<String, dynamic>>[];
    final keptIds = <String>{};

    final active = _activeTiers;
    for (var i = 0; i < active.length; i++) {
      final t = active[i];
      final row = {
        'name': t.nameCtrl.text.trim(),
        'price': double.tryParse(t.priceCtrl.text) ?? 0,
        'quantity_total': int.tryParse(t.qtyCtrl.text) ?? 0,
        'sort_order': i,
      };
      if (t.id == null) {
        add.add(row);
      } else {
        keptIds.add(t.id!);
        update.add({'id': t.id, ...row});
      }
    }
    final remove =
        _originalTierIds.where((id) => !keptIds.contains(id)).toList();

    if (add.isEmpty && update.isEmpty && remove.isEmpty) return;
    await _hostService.manageTiers(
      eventId: eventId,
      add: add,
      update: update,
      remove: remove,
    );
  }

  // ── Media pickers ─────────────────────────────────────────────────────────
  Future<void> _pickCover() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _coverFile = File(picked.path));
  }

  Future<void> _pickGallery() async {
    final total = _galleryFiles.length + _galleryUrls.length;
    if (total >= 5) {
      _toast('Up to 5 gallery photos');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      setState(() {
        for (final img in picked) {
          if (_galleryFiles.length + _galleryUrls.length < 5) {
            _galleryFiles.add(File(img.path));
          }
        }
      });
    }
  }

  // ── Google Places (mirrors CreateExperienceScreen) ─────────────────────────
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final q = _addressController.text;
      if (q.isNotEmpty) {
        _getPlacePredictions(q);
      } else {
        setState(() {
          _placePredictions = [];
          _showPredictions = false;
        });
      }
    });
  }

  // One Places session token per search: reused across autocomplete calls and
  // the details fetch, then rotated so each search is billed as one session.
  String? _placesSession;

  Future<void> _getPlacePredictions(String input) async {
    _placesSession ??= PlacesService.instance.newSessionToken();
    final predictions = await PlacesService.instance.autocomplete(
      input,
      lat: _lat,
      lng: _lng,
      radiusMeters: 30000,
      sessionToken: _placesSession,
    );
    if (!mounted) return;
    setState(() {
      _placePredictions = predictions
          .map((p) => <String, dynamic>{
                'place_id': p.placeId,
                'description': p.description,
                'main_text': p.mainText,
                'secondary_text': p.secondaryText,
              })
          .toList();
      _showPredictions = predictions.isNotEmpty;
    });
  }

  Future<void> _getPlaceDetails(String placeId) async {
    final details = await PlacesService.instance.details(
      placeId,
      sessionToken: _placesSession,
    );
    _placesSession = null; // close the session; next search starts fresh
    if (details == null || !mounted) return;
    setState(() {
      if (_venueController.text.trim().isEmpty) {
        _venueController.text = details.name;
      }
      _addressController.text = details.formattedAddress.isNotEmpty
          ? details.formattedAddress
          : details.name;
      _lat = details.latitude;
      _lng = details.longitude;
      _showPredictions = false;
      _placePredictions = [];
    });
  }

  Future<void> _pickLocationOnMap() async {
    final currentPosition = Position(
      longitude: _lng,
      latitude: _lat,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerModal(initialPosition: currentPosition),
      ),
    );
    if (result is Map) {
      final address = result['address'] as String?;
      final lat = result['latitude'] as double?;
      final lng = result['longitude'] as double?;
      if (lat != null && lng != null) {
        setState(() {
          _lat = lat;
          _lng = lng;
          if (address != null && address.isNotEmpty) {
            _addressController.text = address;
          }
          _showPredictions = false;
        });
      }
    }
  }

  Future<void> _pickDateTime({
    bool isStart = false,
    bool isSalesEnd = false,
  }) async {
    final current = isStart
        ? _startDateTime
        : isSalesEnd
            ? _salesEndDateTime
            : _endDateTime;
    final initial = current ?? _startDateTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startDateTime = dt;
      } else if (isSalesEnd) {
        _salesEndDateTime = dt;
      } else {
        _endDateTime = dt;
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const stepTitles = ['Basics', 'Media', 'When & Where', 'Tickets', 'Review'];
    final isLast = _currentStep == _totalSteps - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_currentStep > 0 ? Icons.arrow_back : Icons.close,
              color: Colors.black87),
          onPressed:
              _currentStep > 0 ? _prevStep : () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit Event' : 'Create Event',
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
            Text(
              'Step ${_currentStep + 1} of $_totalSteps — ${stepTitles[_currentStep]}',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: Colors.grey[200],
            color: AppTheme.primaryColor,
            minHeight: 3,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicsStep(),
                _buildMediaStep(),
                _buildWhenWhereStep(),
                _buildTicketsStep(),
                _buildReviewStep(),
              ],
            ),
          ),
          _buildBottomBar(isLast),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isLast) {
    if (isLast) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: _isEditing
            ? SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _submit(publish: false),
                  child: _isSubmitting
                      ? const _BtnSpinner()
                      : const Text('Save changes'),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _isSubmitting ? null : () => _submit(publish: false),
                      icon: const Icon(Icons.drafts_outlined, size: 18),
                      label: const Text('Save draft'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _isSubmitting ? null : () => _submit(publish: true),
                      icon: _isSubmitting
                          ? const SizedBox.shrink()
                          : const Icon(Icons.publish, size: 18),
                      label: _isSubmitting
                          ? const _BtnSpinner()
                          : const Text('Publish'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _nextStep,
          child: const Text('Continue'),
        ),
      ),
    );
  }

  // ── Step 1: Basics ─────────────────────────────────────────────────────
  Widget _buildBasicsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('What\'s the event?'),
          const SizedBox(height: 24),
          _label('Title'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
                hintText: 'e.g. Sunset Rooftop Jazz Night'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          _label('Description'),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLines: 5,
            decoration: const InputDecoration(
                hintText: 'What\'s happening, who\'s performing, what to expect...'),
          ),
          const SizedBox(height: 24),
          _label('Category'),
          const SizedBox(height: 12),
          if (_loadingCategories)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.map((c) {
                final selected = _categoryKey == c.key;
                return _choiceChip(
                  label: c.display,
                  selected: selected,
                  onTap: () => setState(
                      () => _categoryKey = selected ? null : c.key),
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          _label('Type'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _eventTypes.map((t) {
              final selected = _eventType == t.$1;
              return _choiceChip(
                label: '${t.$2} ${t.$3}',
                selected: selected,
                onTap: () => setState(() => _eventType = t.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Media ──────────────────────────────────────────────────────
  Widget _buildMediaStep() {
    final coverProvider = _coverFile != null
        ? FileImage(_coverFile!) as ImageProvider
        : (_coverUrl != null && _coverUrl!.isNotEmpty
            ? NetworkImage(_coverUrl!)
            : null);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Cover & photos'),
          const SizedBox(height: 8),
          Text('The cover is the first thing guests see.',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 24),
          _label('Cover image'),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickCover,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey[300]!),
                image: coverProvider != null
                    ? DecorationImage(image: coverProvider, fit: BoxFit.cover)
                    : null,
              ),
              child: coverProvider == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 34, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('Tap to add a cover',
                            style: GoogleFonts.inter(color: Colors.grey[500])),
                      ],
                    )
                  : Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close,
                                size: 15, color: Colors.white),
                            onPressed: () => setState(() {
                              _coverFile = null;
                              _coverUrl = null;
                            }),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          _label('Gallery (up to 5)'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: _galleryUrls.length +
                _galleryFiles.length +
                ((_galleryUrls.length + _galleryFiles.length) < 5 ? 1 : 0),
            itemBuilder: (context, i) {
              final total = _galleryUrls.length + _galleryFiles.length;
              if (i == total) {
                return GestureDetector(
                  onTap: _pickGallery,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Icon(Icons.add, color: Colors.grey[400]),
                  ),
                );
              }
              final isExisting = i < _galleryUrls.length;
              final provider = isExisting
                  ? NetworkImage(_galleryUrls[i]) as ImageProvider
                  : FileImage(_galleryFiles[i - _galleryUrls.length]);
              return Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(image: provider, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (isExisting) {
                        _galleryUrls.removeAt(i);
                      } else {
                        _galleryFiles.removeAt(i - _galleryUrls.length);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  // ── Step 3: When & Where ───────────────────────────────────────────────
  Widget _buildWhenWhereStep() {
    final df = DateFormat('EEE, MMM d • h:mm a');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('When & where'),
          const SizedBox(height: 24),
          _label('Starts'),
          const SizedBox(height: 8),
          _dateTimeField(
            value: _startDateTime == null ? null : df.format(_startDateTime!),
            hint: 'Pick start date & time',
            onTap: () => _pickDateTime(isStart: true),
          ),
          const SizedBox(height: 16),
          _label('Ends (optional)'),
          const SizedBox(height: 8),
          _dateTimeField(
            value: _endDateTime == null ? null : df.format(_endDateTime!),
            hint: 'Pick end date & time',
            onTap: () => _pickDateTime(isStart: false),
            onClear:
                _endDateTime == null ? null : () => setState(() => _endDateTime = null),
          ),
          const SizedBox(height: 24),
          _label('Venue name'),
          const SizedBox(height: 8),
          TextField(
            controller: _venueController,
            decoration: const InputDecoration(hintText: 'e.g. The Rooftop, BGC'),
          ),
          const SizedBox(height: 16),
          _label('Address'),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              hintText: 'Search for a place',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: IconButton(
                icon: const Icon(Icons.map_outlined),
                color: AppTheme.primaryColor,
                tooltip: 'Pick on map',
                onPressed: _pickLocationOnMap,
              ),
            ),
          ),
          if (_showPredictions)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: _placePredictions
                    .map((p) => ListTile(
                          leading: const Icon(Icons.location_on_outlined,
                              color: Colors.black54),
                          title: Text(p['main_text'] ?? '',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(p['secondary_text'] ?? '',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey)),
                          onTap: () => _getPlaceDetails(p['place_id']),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.my_location, size: 20, color: Colors.grey[400]),
                const SizedBox(width: 12),
                Text('${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500, color: Colors.grey[800])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTimeField({
    required String? value,
    required String hint,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 20, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? hint,
                style: GoogleFonts.inter(
                    color: value == null ? Colors.grey[500] : Colors.black87,
                    fontWeight:
                        value == null ? FontWeight.normal : FontWeight.w500),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 18, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  // ── Step 4: Tickets ────────────────────────────────────────────────────
  Widget _buildTicketsStep() {
    final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;
    final over = capacity > 0 && _tierQtySum > capacity;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Tickets'),
          const SizedBox(height: 8),
          Text('General admission for now. Add tiers like Early Bird or VIP.',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 24),
          _label('Total capacity'),
          const SizedBox(height: 8),
          TextField(
            controller: _capacityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 120'),
            onChanged: (v) => setState(() {
              // Keep per-order max within capacity (DB CHECK: max <= capacity).
              final cap = int.tryParse(v.trim()) ?? 0;
              if (cap > 0 && _maxPerOrder > cap) _maxPerOrder = cap;
              if (cap > 0 && _minPerOrder > cap) _minPerOrder = cap;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Allocated across tiers',
                  style:
                      GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
              Text('$_tierQtySum / ${capacity == 0 ? '—' : capacity}',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: over ? Colors.red : Colors.grey[800])),
            ],
          ),
          const SizedBox(height: 20),
          _label('Ticket types'),
          const SizedBox(height: 12),
          ..._tiers.asMap().entries.map((e) => _tierCard(e.key, e.value)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _tiers.add(_TierDraft(name: ''))),
            icon: const Icon(Icons.add),
            label: const Text('Add ticket type'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: const BorderSide(color: AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: 28),

          // Per-order limits
          _label('Tickets per order'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stepper(
                  caption: 'Minimum',
                  value: _minPerOrder,
                  onChanged: (v) => setState(() {
                    _minPerOrder = v.clamp(1, 99);
                    if (_maxPerOrder < _minPerOrder) _maxPerOrder = _minPerOrder;
                  }),
                  min: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stepper(
                  caption: 'Maximum',
                  value: _maxPerOrder,
                  onChanged: (v) =>
                      setState(() => _maxPerOrder = v.clamp(_minPerOrder, 99)),
                  min: _minPerOrder,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Sales cutoff
          _label('Ticket sales end'),
          const SizedBox(height: 8),
          _dateTimeField(
            value: _salesEndDateTime == null
                ? null
                : DateFormat('EEE, MMM d • h:mm a').format(_salesEndDateTime!),
            hint: 'Defaults to the event start time',
            onTap: () => _pickDateTime(isSalesEnd: true),
            onClear: _salesEndDateTime == null
                ? null
                : () => setState(() => _salesEndDateTime = null),
          ),
          const SizedBox(height: 28),

          // Registration options (plain toggles — email copy edited on web)
          _label('Registration'),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _requireApproval,
            onChanged: (v) => setState(() {
              _requireApproval = v;
              if (!v) _hideVenueUntilRegistered = false;
            }),
            activeThumbColor: AppTheme.primaryColor,
            title: Text('Require approval',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              'Guests request a spot; you approve or reject each one. Approval emails use the default copy (editable on the web dashboard).',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _hideVenueUntilRegistered,
            onChanged: _requireApproval
                ? (v) => setState(() => _hideVenueUntilRegistered = v)
                : null,
            activeThumbColor: AppTheme.primaryColor,
            title: Text('Hide venue until registered',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              _requireApproval
                  ? 'Exact address is shown only to approved guests.'
                  : 'Turn on "Require approval" first.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required String caption,
    required int value,
    required ValueChanged<int> onChanged,
    required int min,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
                color: value > min ? AppTheme.primaryColor : Colors.grey[300],
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Text('$value',
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.primaryColor,
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tierCard(int index, _TierDraft tier) {
    final canRemove = _tiers.length > 1;
    final sold = tier.soldQty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tier.nameCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Ticket name (e.g. VIP)',
                      isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (canRemove)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: sold > 0
                      ? null // web guard blocks removing a tier with sales
                      : () => setState(() {
                            _tiers.removeAt(index).dispose();
                          }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tier.priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      prefixText: '₱ ', hintText: '0', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: tier.qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      hintText: 'Qty',
                      isDense: true,
                      helperText: sold > 0 ? '$sold sold' : null),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 5: Review ─────────────────────────────────────────────────────
  Widget _buildReviewStep() {
    final df = DateFormat('EEE, MMM d, y • h:mm a');
    final cat = _categories.where((c) => c.key == _categoryKey).firstOrNull;
    final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Review'),
          const SizedBox(height: 8),
          Text(
            _isEditing
                ? 'Save your changes. Publishing is managed from the dashboard.'
                : 'Save as a private draft, or publish to make it public now. A draft still needs every field filled — it just stays hidden until you publish.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          _reviewRow('Title',
              _titleController.text.trim().isEmpty ? '—' : _titleController.text.trim()),
          _reviewRow('Category', cat?.display ?? '—'),
          _reviewRow(
              'Type',
              _eventTypes
                  .firstWhere((t) => t.$1 == _eventType,
                      orElse: () => ('other', '📌', 'Other'))
                  .$3),
          _reviewRow('Starts',
              _startDateTime == null ? '—' : df.format(_startDateTime!)),
          if (_endDateTime != null) _reviewRow('Ends', df.format(_endDateTime!)),
          _reviewRow(
              'Where',
              [_venueController.text.trim(), _addressController.text.trim()]
                  .where((s) => s.isNotEmpty)
                  .join(' · ')),
          _reviewRow('Capacity', capacity == 0 ? '—' : '$capacity'),
          const SizedBox(height: 16),
          _label('Ticket types'),
          const SizedBox(height: 8),
          ..._activeTiers.map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t.nameCtrl.text.trim(),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                    Text(
                        '₱${t.priceCtrl.text.isEmpty ? '0' : t.priceCtrl.text} · ${t.qtyCtrl.text.isEmpty ? '0' : t.qtyCtrl.text} qty',
                        style: GoogleFonts.inter(color: Colors.grey[700])),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Small UI helpers ────────────────────────────────────────────────────
  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withOpacity(0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: selected ? AppTheme.primaryColor : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87));

  Widget _label(String text) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87));
}

class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
}

/// Mutable draft for one ticket tier while editing. [id] is null for a
/// not-yet-persisted tier; [soldQty] gates destructive edits in the UI.
class _TierDraft {
  String? id;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController qtyCtrl;
  int soldQty;

  _TierDraft({
    this.id,
    String name = '',
    String price = '',
    String qty = '',
    this.soldQty = 0,
  })  : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price),
        qtyCtrl = TextEditingController(text: qty);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    qtyCtrl.dispose();
  }
}
