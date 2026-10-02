import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSupremeCourtIndexUrl =
    'https://raw.githubusercontent.com/ghgfcrcgrf57566-beep/Encyclopedia-of-Yemeni-Law/main/sc_books.json';

const _gold = Color(0xFFD4AF37);
const _goldLight = Color(0xFFF0D78A);
const _goldDark = Color(0xFF8A671C);
const _bg = Color(0xFF121212);
const _surface = Color(0xFF1A1A1A);
