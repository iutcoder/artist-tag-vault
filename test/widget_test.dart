import 'package:artist_tag_vault/src/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application root is a Flutter widget', () {
    expect(const ArtistTagVaultApp(), isA<StatelessWidget>());
  });
}
