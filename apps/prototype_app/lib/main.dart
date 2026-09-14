import 'package:flutter/material.dart';
import 'prototype_app.dart';

void main() {
  final direction = Uri.base.queryParameters['direction'] ?? 'a';
  runApp(PrototypeApp(initialDirection: direction));
}
