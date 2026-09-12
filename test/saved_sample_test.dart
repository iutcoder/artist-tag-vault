import 'dart:io';

import 'package:artist_tag_vault/src/models/saved_sample.dart';
import 'package:flutter_test/flutter_test.dart';

SavedSample sampleWithPrompt(String prompt) => SavedSample(
  file: File('sample.png'),
  artist: 'sample',
  modelId: 'model',
  createdAt: DateTime(2026),
  metadata: {'prompt': prompt},
);

void main() {
  test('classifies exact 1girl and 1boy prompt tags', () {
    expect(sampleWithPrompt('artist:a, 1girl').subject, SampleSubject.female);
    expect(sampleWithPrompt('artist:a, 1boy').subject, SampleSubject.male);
  });

  test('mixed, absent, and longer tags are others', () {
    expect(
      sampleWithPrompt('1girl, 1boy, artist:a').subject,
      SampleSubject.others,
    );
    expect(sampleWithPrompt('artist:a').subject, SampleSubject.others);
    expect(sampleWithPrompt('11girls, artist:a').subject, SampleSubject.others);
  });
}
