import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

/// Converter for Uint8List to handle binary data in JSON serialization
class Uint8ListConverter implements JsonConverter<Uint8List?, List<int>?> {
  const Uint8ListConverter();

  @override
  Uint8List? fromJson(List<int>? json) {
    return json == null ? null : Uint8List.fromList(json);
  }

  @override
  List<int>? toJson(Uint8List? object) {
    return object?.toList();
  }
}

/// Converter for nullable `List<Uint8List>` to handle multiple binary data
class ListUint8ListConverterNullAble
    implements JsonConverter<List<Uint8List>?, List<List<int>>?> {
  const ListUint8ListConverterNullAble();

  @override
  List<Uint8List>? fromJson(List<List<int>>? json) {
    if (json == null) {
      return null;
    }

    final converter = <Uint8List>[];

    for (var item in json) {
      converter.add(Uint8List.fromList(item));
    }

    return converter;
  }

  @override
  List<List<int>>? toJson(List<Uint8List>? object) {
    if (object == null) {
      return null;
    }

    final converter = <List<int>>[];

    for (var item in object) {
      converter.add(item.toList());
    }

    return converter.toList();
  }
}

/// Converter for non-nullable `List<Uint8List>` to handle multiple binary data
class ListUint8ListConverter
    implements JsonConverter<List<Uint8List>, List<List<int>>> {
  const ListUint8ListConverter();

  @override
  List<Uint8List> fromJson(List<List<int>> json) {
    final converter = <Uint8List>[];

    for (var item in json) {
      converter.add(Uint8List.fromList(item));
    }

    return converter;
  }

  @override
  List<List<int>> toJson(List<Uint8List> object) {
    final converter = <List<int>>[];

    for (var item in object) {
      converter.add(item.toList());
    }

    return converter.toList();
  }
}

/// Converter for status codes from string to int
class StatusConverter implements JsonConverter<int?, String?> {
  const StatusConverter();

  @override
  int? fromJson(String? status) {
    if (status == null) return null;
    return int.tryParse(status) ?? -1;
  }

  @override
  String? toJson(int? status) {
    if (status == null) return null;
    return status.toString();
  }
}

/// Converter for string to int conversion
class StringToIntConverter implements JsonConverter<int?, String?> {
  const StringToIntConverter();

  @override
  int? fromJson(String? json) {
    if (json == null) return null;
    return int.tryParse(json);
  }

  @override
  String? toJson(int? object) {
    if (object == null) return null;
    return object.toString();
  }
}
