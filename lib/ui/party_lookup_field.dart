import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';

/// Searchable, in-place party selector. It never navigates to another screen.
/// The caller supplies its existing customers/suppliers API search function.
class PartyLookupField extends StatefulWidget {
  const PartyLookupField({
    super.key,
    required this.label,
    required this.selected,
    required this.search,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final Json? selected;
  final Future<List<Json>> Function(String query) search;
  final ValueChanged<Json?> onSelected;
  final bool enabled;

  @override
  State<PartyLookupField> createState() => _PartyLookupFieldState();
}

class _PartyLookupFieldState extends State<PartyLookupField> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<Json> _matches = [];
  bool _expanded = false;
  bool _loading = false;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: '${widget.selected?['name'] ?? ''}');
  }

  @override
  void didUpdateWidget(covariant PartyLookupField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep a selected party passed by the parent/draft in sync with the field.
    if (oldWidget.selected?['id'] != widget.selected?['id'] &&
        widget.selected != null) {
      final name = '${widget.selected!['name']}';
      _text.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }
    if (oldWidget.enabled && !widget.enabled) {
      _debounce?.cancel();
      _request++;
      _expanded = false;
      _loading = false;
      _failed = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _request++;
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _close() {
    _debounce?.cancel();
    _request++;
    if (!mounted) return;
    setState(() {
      _expanded = false;
      _loading = false;
      _failed = false;
    });
  }

  void _open() {
    if (!widget.enabled) return;
    if (!_expanded) setState(() => _expanded = true);
    _find(_text.text);
  }

  void _find(String input) {
    _debounce?.cancel();
    final current = ++_request;
    setState(() {
      _expanded = true;
      _loading = true;
      _failed = false;
      _matches = [];
    });
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final matches = await widget.search(input.trim());
        if (!mounted || current != _request) return;
        setState(() {
          _matches = matches;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || current != _request) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  void _onChanged(String input) {
    if (widget.selected != null &&
        input.trim() != '${widget.selected!['name']}') {
      // Never submit an old party ID with a newly typed name.
      widget.onSelected(null);
    }
    _find(input);
  }

  void _choose(Json customer) {
    _debounce?.cancel();
    _request++;
    final name = '${customer['name']}';
    _text.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
    widget.onSelected(customer);
    _focus.unfocus();
    setState(() {
      _expanded = false;
      _matches = [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.label;
    return TapRegion(
      onTapOutside: (_) {
        if (_expanded) _close();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        TextFormField(
          key: const Key('transaction-party-search'),
          controller: _text,
          focusNode: _focus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'اكتب اسم $name أو اضغط لعرض الأسماء',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: _expanded ? 'إغلاق قائمة الأسماء' : 'عرض قائمة الأسماء',
              onPressed: widget.enabled
                  ? () {
                      if (_expanded) {
                        _close();
                        _focus.unfocus();
                      } else {
                        _focus.requestFocus();
                        _open();
                      }
                    }
                  : null,
              icon: Icon(
                widget.selected != null && !_expanded
                    ? Icons.check_circle_outline
                    : _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
              ),
            ),
          ),
          onTap: _open,
          onChanged: _onChanged,
          onFieldSubmitted: (_) {
            // Typing a name alone does not select a party; a suggestion must
            // be tapped to store the correct party ID.
            _focus.unfocus();
          },
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _failed
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('تعذّر تحميل الأسماء. تأكد من الاتصال وحاول مجددًا.'),
                          ),
                          TextButton.icon(
                            onPressed: () => _find(_text.text),
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      )
                    : _matches.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_text.text.trim().isEmpty
                                ? 'لا يوجد $name مسجل حاليًا.'
                                : 'لا توجد أسماء مطابقة. جرّب كتابة اسم آخر.'),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 252),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _matches.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final item = _matches[i];
                                final nickname = '${item['nickname'] ?? ''}'.trim();
                                final phone = '${item['phone'] ?? ''}'.trim();
                                return ListTile(
                                  dense: true,
                                  key: ValueKey('party-option-${item['id']}'),
                                  leading: const Icon(Icons.person_outline),
                                  title: Text('${item['name']}'),
                                  subtitle: nickname.isEmpty && phone.isEmpty
                                      ? null
                                      : Text([
                                          if (nickname.isNotEmpty) nickname,
                                          if (phone.isNotEmpty) phone,
                                        ].join(' · ')),
                                  onTap: () => _choose(item),
                                );
                              },
                            ),
                          ),
          ),
        if (widget.selected != null && !_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'تم اختيار $name: ${widget.selected!['name']}',
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
