import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/search_results_screen.dart';



// 카테고리 목록을 제공하는 FutureProvider
final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final campaignService = ref.watch(campaignServiceProvider);
  return campaignService.fetchCategories();
});