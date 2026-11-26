enum LegalDocumentKind {
  terms,
  privacy;

  static const version = '2026-11-16';

  String get title => switch (this) {
    terms => 'Terms of Use',
    privacy => 'Privacy Policy',
  };

  String get path => switch (this) {
    terms => '/legal/terms',
    privacy => '/legal/privacy',
  };

  String get assetPath => switch (this) {
    terms => 'assets/legal/terms-of-use.txt',
    privacy => 'assets/legal/privacy-policy.txt',
  };

  int get sectionCount => this == terms ? 11 : 8;

  static LegalDocumentKind? forUri(Uri uri) {
    for (final kind in values) {
      if (uri == Uri(path: kind.path)) return kind;
    }
    return null;
  }
}

enum LegalBlockStyle { section, subheading, paragraph }

class LegalBlock {
  const LegalBlock(this.text, this.style);
  final String text;
  final LegalBlockStyle style;
}

class LegalDocumentContent {
  const LegalDocumentContent({
    required this.officialTitle,
    required this.dates,
    required this.blocks,
  });

  final String officialTitle;
  final List<String> dates;
  final List<LegalBlock> blocks;

  Iterable<LegalBlock> get sections =>
      blocks.where((block) => block.style == LegalBlockStyle.section);

  factory LegalDocumentContent.parse(LegalDocumentKind kind, String source) {
    final lines = source
        .replaceAll('\u200b', '')
        .split('\n')
        .map((line) => line.trim())
        .toList();
    if (lines.length < 3 || lines.first != kind.title) {
      throw const FormatException('legal_document_invalid');
    }
    final dates = <String>[];
    final blocks = <LegalBlock>[];
    var nextSection = 1;
    for (final line in lines.skip(2)) {
      if (line.isEmpty) continue;
      if (line.startsWith('Effective Date:') ||
          line.startsWith('Last Updated:')) {
        dates.add(line);
        continue;
      }
      final heading = RegExp(r'^(\d+)\.\s+([^:]+)$').firstMatch(line);
      if (heading != null && int.parse(heading[1]!) == nextSection) {
        blocks.add(LegalBlock(line, LegalBlockStyle.section));
        nextSection++;
      } else if (RegExp(r'^[A-E]\.\s').hasMatch(line) ||
          line == 'Safety & Legal Exceptions:') {
        blocks.add(LegalBlock(line, LegalBlockStyle.subheading));
      } else {
        blocks.add(LegalBlock(line, LegalBlockStyle.paragraph));
      }
    }
    if (nextSection != kind.sectionCount + 1 ||
        !dates.contains('Effective Date: November 16, 2026')) {
      throw const FormatException('legal_document_incomplete');
    }
    return LegalDocumentContent(
      officialTitle: lines[1],
      dates: List.unmodifiable(dates),
      blocks: List.unmodifiable(blocks),
    );
  }
}
