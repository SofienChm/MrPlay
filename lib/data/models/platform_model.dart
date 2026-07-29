import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

class PlatformModel extends Equatable {
  final String name;
  final String url;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String category;

  const PlatformModel({
    required this.name,
    required this.url,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.category,
  });

  @override
  List<Object?> get props => [name, url, category];
}
