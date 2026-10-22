import 'dart:convert';

/// UTF-8 and JSON frames may be split or coalesced by an OS pipe.
Stream<String> messageLines(Stream<List<int>> bytes) =>
    bytes.transform(utf8.decoder).transform(const LineSplitter());
