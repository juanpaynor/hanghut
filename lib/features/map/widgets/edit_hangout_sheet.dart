import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bitemates/core/services/places_service.dart';
import 'package:bitemates/core/services/table_service.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/features/map/models/hangout_edit.dart';

/// Host-only sheet for changing a hangout after it exists.
///
/// This is the other half of the suggestion loop: "I'm in" creates the hangout
/// with a system-chosen venue and time, so the host needs somewhere to correct
/// them. It is also the only repair tool for the hangouts already sitting at
/// (0, 0) — a host can finally put one back on the map.
///
/// **Only changed fields are sent.** The RPC pushes "Plans changed" to everyone
/// who committed whenever the time or the place arrives, so echoing back an
/// unchanged venue alongside a typo fix would notify the whole group for
/// nothing. Everything is compared against the values this sheet opened with.
///
/// The venue is a unit — name, coordinates and address move together, which is
/// what keeps the stored address from describing the previous place. So the
/// venue field is read-only text plus a search; it is not freely typeable,
/// because a typed name with the old coordinates is how a hangout ends up
/// pinned somewhere nobody agreed to.
///
/// Icons used here — `close`, `calendar_today_rounded`, `schedule`,
/// `location_on_rounded`, `place_outlined`, `search`, `chevron_right`,
/// `keyboard_arrow_down`, `add`, `remove`, `error_outline`,
/// `people_alt_outlined` — are all present in base release 11305a4, so this
/// ships as a Shorebird patch rather than needing a full release.
class EditHangoutSheet extends StatefulWidget {
  final Map<String, dynamic> table;

  const EditHangoutSheet({super.key, required this.table});

  /// Returns true when something was actually saved, so the caller knows to
  /// reload rather than guessing.
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> table,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditHangoutSheet(table: table),
    );
    return saved == true;
  }

  @override
  State<EditHangoutSheet> createState() => _EditHangoutSheetState();
}

class _EditHangoutSheetState extends State<EditHangoutSheet> {
  final _service = TableService();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _venueSearchController = TextEditingController();

  // What the sheet opened with. The diff on save is taken against these, not
  // against the live row, so a change made elsewhere mid-edit cannot be
  // silently reverted by a field this host never touched.
  late final String _originalTitle;
  late final String _originalDescription;
  late final DateTime _originalDateTime;
  late final String _originalVenueName;
  late final int _originalMaxGuests;

  late DateTime _dateTime;
  late int _maxGuests;

  /// Set only when a new venue has been picked. Null means "venue unchanged",
  /// which is what stops a save from pushing a location notification.
  String? _newVenueName;
  String? _newVenueAddress;
  double? _newVenueLat;
  double? _newVenueLng;

  bool _searching = false;
  List<PlacePrediction> _predictions = [];
  Timer? _debounce;

  /// Whether the venue search is revealed. It starts closed because an empty
  /// search box parked permanently under the venue reads as though no place is
  /// set, and most edits never touch the place at all.
  bool _searchOpen = false;

  /// One Places session token per search, rotated after each pick so the
  /// search bills as a single session rather than per keystroke.
  String? _placesSession;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _originalTitle = (widget.table['title'] as String?)?.trim() ?? '';
    _originalDescription =
        (widget.table['description'] as String?)?.trim() ?? '';
    _originalVenueName =
        (widget.table['location_name'] as String?)?.trim() ??
        (widget.table['venue_name'] as String?)?.trim() ??
        '';

    final raw = widget.table['datetime'] ?? widget.table['scheduled_time'];
    _originalDateTime =
        DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 2));
    _dateTime = _originalDateTime;

    final guests = widget.table['max_guests'] ?? widget.table['max_capacity'];
    // Doubles arrive here from JSON on some paths — see marker_lookup.dart for
    // the crash a bare cast caused.
    _originalMaxGuests = (guests is num) ? guests.toInt() : 6;
    _maxGuests = _originalMaxGuests;

    _titleController = TextEditingController(text: _originalTitle);
    _descriptionController = TextEditingController(text: _originalDescription);
    _venueSearchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _venueSearchController.dispose();
    super.dispose();
  }

  // ─── What changed ──────────────────────────────────

  String get _venueName => _newVenueName ?? _originalVenueName;

  /// Recomputed on every build rather than tracked incrementally, so the Save
  /// button and the notification notice can never disagree with what is
  /// actually about to be sent.
  HangoutEditDiff get _diff => HangoutEditDiff.between(
    originalTitle: _originalTitle,
    currentTitle: _titleController.text,
    originalDescription: _originalDescription,
    currentDescription: _descriptionController.text,
    originalDateTime: _originalDateTime,
    currentDateTime: _dateTime,
    originalMaxGuests: _originalMaxGuests,
    currentMaxGuests: _maxGuests,
    newVenueName: _newVenueName,
    newVenueAddress: _newVenueAddress,
    newVenueLat: _newVenueLat,
    newVenueLng: _newVenueLng,
  );

  bool get _venueChanged => _newVenueName != null;

  // ─── Venue search ──────────────────────────────────

  void _onSearchChanged() {
    _debounce?.cancel();
    final text = _venueSearchController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _predictions = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _predict(text));
  }

  Future<void> _predict(String input) async {
    setState(() => _searching = true);
    _placesSession ??= PlacesService.instance.newSessionToken();
    final results = await PlacesService.instance.autocomplete(
      input,
      lat: _currentLat,
      lng: _currentLng,
      radiusMeters: 30000,
      sessionToken: _placesSession,
    );
    if (!mounted) return;
    setState(() {
      _predictions = results;
      _searching = false;
    });
  }

  /// Bias the search toward where the hangout already is, unless it is at the
  /// null island — in which case there is nothing to bias toward and an
  /// unbiased PH-wide search is the honest behaviour.
  ///
  /// Both column spellings are read because this sheet is reached from two
  /// shapes of row: a marker tap carries the `map_ready_tables` view
  /// (`location_lat` / `location_lng`), while a notification or the
  /// suggestion accept carries the base table (`latitude` / `longitude`).
  /// Reading only one spelling would treat half the hangouts as unplaced.
  double? get _currentLat {
    final lat = widget.table['latitude'] ?? widget.table['location_lat'];
    final lng = widget.table['longitude'] ?? widget.table['location_lng'];
    if (lat is! num || lng is! num) return null;
    if (lat == 0 && lng == 0) return null;
    return lat.toDouble();
  }

  double? get _currentLng {
    if (_currentLat == null) return null;
    final lng = widget.table['longitude'] ?? widget.table['location_lng'];
    return (lng is num) ? lng.toDouble() : null;
  }

  Future<void> _pick(PlacePrediction p) async {
    final details = await PlacesService.instance.details(
      p.placeId,
      sessionToken: _placesSession,
    );
    _placesSession = null; // close the session; the next search starts fresh
    if (!mounted) return;
    if (details == null) {
      _toast('Could not read that place. Try another.');
      return;
    }
    // A pick with no coordinates is the exact shape that produced the (0, 0)
    // rows this sheet exists to repair, so it is refused here too.
    if (details.latitude == 0 && details.longitude == 0) {
      _toast('That spot could not be placed on the map.');
      return;
    }
    setState(() {
      _newVenueName = details.name.isNotEmpty ? details.name : p.description;
      _newVenueAddress = details.formattedAddress;
      _newVenueLat = details.latitude;
      _newVenueLng = details.longitude;
      _predictions = [];
      _venueSearchController.clear();
      // Collapse back to the venue card: the pick is the answer, so leaving
      // the search open invites a second one over the top of it.
      _searchOpen = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _clearNewVenue() {
    setState(() {
      _newVenueName = null;
      _newVenueAddress = null;
      _newVenueLat = null;
      _newVenueLng = null;
    });
  }

  // ─── Date / time ───────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime.isBefore(now) ? now : _dateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => _pickerTheme(ctx, child),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dateTime.hour,
        _dateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
      builder: (ctx, child) => _pickerTheme(ctx, child),
    );
    if (picked == null) return;
    setState(() {
      _dateTime = DateTime(
        _dateTime.year,
        _dateTime.month,
        _dateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Widget _pickerTheme(BuildContext ctx, Widget? child) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return Theme(
      data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryColor,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      child: child!,
    );
  }

  // ─── Save ──────────────────────────────────────────

  Future<void> _save() async {
    final diff = _diff;
    if (diff.isEmpty || _saving) return;

    // Caught here as well as server-side: a host who picks a past time gets
    // told before the round trip, and the round trip cannot be the only guard
    // because a sheet left open can make any time stale.
    if (diff.timeChanged && _dateTime.isBefore(DateTime.now())) {
      _toast('Pick a time in the future.');
      return;
    }

    setState(() => _saving = true);

    final result = await _service.updateHangout(
      tableId: widget.table['id'] as String,
      title: diff.title,
      description: diff.description,
      datetime: diff.datetime,
      locationName: diff.locationName,
      latitude: diff.latitude,
      longitude: diff.longitude,
      venueAddress: diff.venueAddress,
      maxGuests: diff.maxGuests,
    );

    if (!mounted) return;

    if (!result.ok) {
      // The RPC's refusals are written for the host to read — "You already
      // have 4 people — raise the limit instead" names the fix. Keep the
      // sheet open on them so the edit is not lost.
      setState(() => _saving = false);
      _toast(result.message);
      return;
    }

    Navigator.of(context).pop(true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }


  // ─── Build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(context);
    // One diff for the whole frame, so the Save button, its label and the
    // notification notice are all describing the same pending save.
    final diff = _diff;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _grabber(p),
            _header(p),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(p, 'NAME'),
                    _titleField(p),
                    _section(p, 'PLACE'),
                    _venueBlock(p),
                    _section(p, 'TIME'),
                    _whenRow(p),
                    _section(p, 'SIZE'),
                    _guestStepper(p),
                    _section(p, 'NOTES'),
                    _notesField(p),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            // The save bar sits outside the scroll view so it is reachable
            // without scrolling past the notes field, and so the warning
            // about notifying people cannot be scrolled out of sight before
            // the button that triggers it is pressed.
            _saveBar(p, diff),
          ],
        ),
      ),
    );
  }

  Widget _grabber(_Palette p) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: p.hairline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  Widget _header(_Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 10, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit hangout',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Only you can change this',
                  style: TextStyle(fontSize: 12.5, color: p.subtext),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            icon: Icon(Icons.close, size: 21, color: p.subtext),
          ),
        ],
      ),
    );
  }

  /// Micro-label above each block. Short enough to scan down the left edge,
  /// which is what makes a form of five fields read as five decisions.
  Widget _section(_Palette p, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 7),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: p.subtext,
      ),
    ),
  );

  BoxDecoration _cardDecoration(_Palette p, {bool highlighted = false}) =>
      BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? p.accent.withValues(alpha: 0.6) : p.hairline,
          width: highlighted ? 1.4 : 1,
        ),
      );

  Widget _titleField(_Palette p) {
    return Container(
      decoration: _cardDecoration(p),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: _titleController,
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
        decoration: InputDecoration(
          hintText: 'Give it a name',
          hintStyle: TextStyle(fontWeight: FontWeight.w400, color: p.hint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _notesField(_Palette p) {
    return Container(
      decoration: _cardDecoration(p),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: _descriptionController,
        onChanged: (_) => setState(() {}),
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(fontSize: 14.5, height: 1.35, color: p.text),
        decoration: InputDecoration(
          hintText: 'What should people know? Optional.',
          hintStyle: TextStyle(color: p.hint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  /// The current venue, and a search that replaces it.
  ///
  /// The search is hidden behind "Change" rather than always on screen: an
  /// empty search box permanently parked under the venue reads as though the
  /// venue is missing, and most edits never touch the place at all.
  ///
  /// The name is never editable on its own. The stored address and coordinates
  /// come from the pick, so a typed-over name would describe one place while
  /// the map pin pointed at another.
  Widget _venueBlock(_Palette p) {
    final atNullIsland = _currentLat == null && !_venueChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: _cardDecoration(p, highlighted: _venueChanged),
          padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: p.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _venueName.isEmpty ? 'No place set' : _venueName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: p.text,
                      ),
                    ),
                    if (_subVenueLine case final line?) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: _venueChanged ? p.accent : p.subtext,
                          fontWeight: _venueChanged
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _venueChanged
                  ? TextButton(
                      onPressed: () {
                        _clearNewVenue();
                        setState(() => _searchOpen = false);
                      },
                      style: _tinyButtonStyle(p.subtext),
                      child: const Text('Undo'),
                    )
                  : TextButton(
                      onPressed: () {
                        setState(() => _searchOpen = !_searchOpen);
                        if (!_searchOpen) {
                          _venueSearchController.clear();
                          FocusScope.of(context).unfocus();
                        }
                      },
                      style: _tinyButtonStyle(p.accent),
                      child: Text(_searchOpen ? 'Cancel' : 'Change'),
                    ),
            ],
          ),
        ),

        // The only honest prompt for the (0, 0) rows: the hangout is not on
        // the map at all, and no amount of renaming fixes that.
        if (atNullIsland) ...[
          const SizedBox(height: 8),
          _notice(
            p,
            Icons.error_outline,
            'This hangout is not on the map yet. Tap Change and search the '
            'spot so people can find it.',
            tone: p.warning,
          ),
        ],

        if (_searchOpen || _predictions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: _cardDecoration(p),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.search, size: 19, color: p.subtext),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _venueSearchController,
                    autofocus: true,
                    style: TextStyle(fontSize: 14.5, color: p.text),
                    decoration: InputDecoration(
                      hintText: 'Search a place',
                      hintStyle: TextStyle(color: p.hint),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_searching)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.accent,
                    ),
                  ),
              ],
            ),
          ),
        ],

        if (_predictions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: _cardDecoration(p),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, place) in _predictions.take(5).indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: p.hairline),
                  InkWell(
                    onTap: () => _pick(place),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                      child: Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 17,
                            color: p.subtext,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  place.mainText.isNotEmpty
                                      ? place.mainText
                                      : place.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: p.text,
                                  ),
                                ),
                                if (place.secondaryText.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    place.secondaryText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: p.subtext,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: p.hint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The second line under the venue name: the new address once a place has
  /// been picked, otherwise the address already stored. Null when there is
  /// none, so the card collapses to one line rather than showing a gap.
  String? get _subVenueLine {
    if (_venueChanged) {
      final addr = _newVenueAddress?.trim();
      return (addr != null && addr.isNotEmpty) ? addr : 'New place';
    }
    final stored = (widget.table['venue_address'] as String?)?.trim();
    return (stored != null && stored.isNotEmpty) ? stored : null;
  }

  ButtonStyle _tinyButtonStyle(Color color) => TextButton.styleFrom(
    foregroundColor: color,
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  );

  Widget _whenRow(_Palette p) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _chip(
            p,
            icon: Icons.calendar_today_rounded,
            label: DateFormat('EEE, d MMM').format(_dateTime),
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _chip(
            p,
            icon: Icons.schedule,
            label: DateFormat('h:mm a').format(_dateTime),
            onTap: _pickTime,
          ),
        ),
      ],
    );
  }

  Widget _chip(
    _Palette p, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: _cardDecoration(p),
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
          child: Row(
            children: [
              Icon(icon, size: 16, color: p.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down, size: 18, color: p.hint),
            ],
          ),
        ),
      ),
    );
  }

  /// Capacity cannot drop below the people already in — the server owns that
  /// rule, since only it knows the live count, and its refusal names the
  /// number. The floor of 2 here is just "a hangout needs someone else".
  Widget _guestStepper(_Palette p) {
    return Container(
      decoration: _cardDecoration(p),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          _stepButton(
            p,
            Icons.remove,
            _maxGuests > 2 ? () => setState(() => _maxGuests--) : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_maxGuests',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: p.text,
                  ),
                ),
                Text(
                  // "Up to" because this is a ceiling, not a headcount — the
                  // bare number read as "7 people are coming".
                  _maxGuests == 1 ? 'person, max' : 'people, max',
                  style: TextStyle(fontSize: 11.5, color: p.subtext),
                ),
              ],
            ),
          ),
          _stepButton(
            p,
            Icons.add,
            _maxGuests < 100 ? () => setState(() => _maxGuests++) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepButton(_Palette p, IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? p.accent.withValues(alpha: 0.13) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: enabled ? p.accent : p.hint),
        ),
      ),
    );
  }

  Widget _notice(
    _Palette p,
    IconData icon,
    String text, {
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: p.isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: p.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(_Palette p, HangoutEditDiff diff) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (diff.notifiesMembers) ...[
            _notice(
              p,
              Icons.people_alt_outlined,
              diff.timeChanged && diff.venueChanged
                  ? 'Everyone who is in will be told the place and time changed.'
                  : diff.venueChanged
                  ? 'Everyone who is in will be told the place changed.'
                  : 'Everyone who is in will be told the time changed.',
              tone: p.accent,
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: (diff.isNotEmpty && !_saving) ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: p.card,
                disabledForegroundColor: p.hint,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      diff.isNotEmpty ? 'Save changes' : 'No changes yet',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's colours in one place, resolved once per build.
///
/// Flat `Colors.white10` panels on the dark surface read as muddy and give
/// every field the same weight; a lifted card plus a hairline border is what
/// separates "tap this" from "read this" in both themes.
class _Palette {
  final bool isDark;
  final Color surface;
  final Color card;
  final Color hairline;
  final Color text;
  final Color subtext;
  final Color hint;
  final Color accent;
  final Color warning;

  const _Palette({
    required this.isDark,
    required this.surface,
    required this.card,
    required this.hairline,
    required this.text,
    required this.subtext,
    required this.hint,
    required this.accent,
    required this.warning,
  });

  factory _Palette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const _Palette(
            isDark: true,
            // Matches AppTheme.darkSurface: this opens next to
            // TableCompactModal, and a sheet at a different temperature than
            // the one it came from reads as a different app.
            surface: AppTheme.darkSurface,
            card: Color(0xFF242428),
            hairline: Color(0xFF32323A),
            text: Colors.white,
            subtext: Color(0xFF9A9AA6),
            hint: Color(0xFF6A6A76),
            accent: Color(0xFF8E88FF),
            warning: Color(0xFFE8A33D),
          )
        : _Palette(
            isDark: false,
            surface: Colors.white,
            card: const Color(0xFFF6F6FA),
            hairline: const Color(0xFFE4E4ED),
            text: AppTheme.textPrimary,
            subtext: AppTheme.textSecondary,
            hint: const Color(0xFFA6A6B4),
            accent: AppTheme.primaryColor,
            warning: const Color(0xFFC77A10),
          );
  }
}
