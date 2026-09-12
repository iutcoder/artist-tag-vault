import 'dart:async';

import 'package:artist_tag_vault/src/services/danbooru_autocomplete.dart';
import 'package:flutter/material.dart';

class DanbooruArtistField extends StatelessWidget {
  const DanbooruArtistField({
    required this.controller,
    required this.focusNode,
    required this.service,
    required this.enabled,
    required this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DanbooruAutocompleteService service;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          RawAutocomplete<DanbooruArtistSuggestion>(
        textEditingController: controller,
        focusNode: focusNode,
        displayStringForOption: (option) => option.value,
        optionsBuilder: (value) async {
          final query = value.text.trim();
          if (!enabled || query.length < 2) return const [];
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (controller.text.trim() != query) return const [];
          try {
            final results = await service.suggestArtists(query);
            return controller.text.trim() == query ? results : const [];
          } on Exception {
            // Autocomplete is optional. Manual entry must remain available when
            // Danbooru is offline, rate-limited, or blocked by the network.
            return const [];
          }
        },
        fieldViewBuilder: (context, fieldController, fieldFocus, submit) {
          return TextField(
            controller: fieldController,
            focusNode: fieldFocus,
            enabled: enabled,
            onSubmitted: (value) {
              submit();
              onSubmitted(value);
            },
            decoration: const InputDecoration(
              labelText: 'Artist name',
              prefixText: 'artist:',
              hintText: 'artist name',
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final values = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 12,
              color: const Color(0xFF202038),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                  maxHeight: 280,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: values.length,
                  itemBuilder: (context, index) {
                    final suggestion = values[index];
                    return InkWell(
                      onTap: () => onSelected(suggestion),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'artist:${suggestion.value}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
