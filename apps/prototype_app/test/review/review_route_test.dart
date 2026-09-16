import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_route.dart';

void main() {
  group('parseReviewRoute', () {
    test('treats /review with a client as review mode', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/review?client=prototype-demo')),
        const ReviewRouteRequest(isReviewMode: true, clientId: 'prototype-demo'),
      );
    });

    test('treats /review without a client as review mode with a null client', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/review')),
        const ReviewRouteRequest(isReviewMode: true),
      );
    });

    test('tolerates a trailing slash on the review path', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/review/?client=prototype-demo')),
        const ReviewRouteRequest(isReviewMode: true, clientId: 'prototype-demo'),
      );
    });

    test('normal root without a client stays prototype mode with a null client', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/')),
        const ReviewRouteRequest(isReviewMode: false),
      );
    });

    test('normal root with a client keeps the client but stays prototype mode', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/?client=prototype-demo')),
        const ReviewRouteRequest(isReviewMode: false, clientId: 'prototype-demo'),
      );
    });

    test('hash-based review URL parses the fragment path and query', () {
      expect(
        parseReviewRoute(Uri.parse('https://host/#/review?client=x')),
        const ReviewRouteRequest(isReviewMode: true, clientId: 'x'),
      );
    });

    test('hash-based review URL without a client keeps a null client', () {
      expect(
        parseReviewRoute(Uri.parse('https://host/#/review')),
        const ReviewRouteRequest(isReviewMode: true),
      );
    });

    test('a direction query does not affect review detection', () {
      expect(
        parseReviewRoute(Uri.parse('https://example.test/review?client=x&direction=b')),
        const ReviewRouteRequest(isReviewMode: true, clientId: 'x'),
      );
      expect(
        parseReviewRoute(Uri.parse('https://example.test/?direction=b')),
        const ReviewRouteRequest(isReviewMode: false),
      );
    });

    test('never substitutes a default client id', () {
      final request = parseReviewRoute(Uri.parse('https://example.test/review'));

      expect(request.clientId, isNull);
    });

    test('value equality compares mode and client', () {
      expect(
        const ReviewRouteRequest(isReviewMode: true, clientId: 'x'),
        equals(const ReviewRouteRequest(isReviewMode: true, clientId: 'x')),
      );
      expect(
        const ReviewRouteRequest(isReviewMode: true, clientId: 'x'),
        isNot(equals(const ReviewRouteRequest(isReviewMode: true, clientId: 'y'))),
      );
      expect(
        const ReviewRouteRequest(isReviewMode: true),
        isNot(equals(const ReviewRouteRequest(isReviewMode: false))),
      );
    });
  });
}
