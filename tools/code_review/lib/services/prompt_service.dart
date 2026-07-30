import 'dart:io';
import 'package:path/path.dart' as path;
import '../core/constants.dart';
import '../core/enums.dart';
import '../utils/file_analyzer.dart';

/// Service for managing review prompts
class PromptService {
  /// Load the review prompt from markdown file
  static Future<String> loadReviewPrompt() async {
    final promptFile = File(
      path.join(
        CodeReviewConstants.toolDir,
        CodeReviewConstants.promptFileName,
      ),
    );

    if (await promptFile.exists()) {
      return promptFile.readAsString();
    } else {
      // Fallback prompt if file doesn't exist
      return _getFallbackPrompt();
    }
  }

  /// Build complete prompt for code review
  static Future<String> buildReviewPrompt({
    required String code,
    required String filePath,
    List<String> focusAreas = const [],
    String language = 'en',
  }) async {
    final basePrompt = await loadReviewPrompt();
    final focusText = focusAreas.isNotEmpty
        ? 'Focus specifically on: ${focusAreas.join(', ')}. '
        : '';

    final fileType = FileAnalyzer.getFileType(filePath);
    final layer = FileAnalyzer.getArchitectureLayer(filePath);

    // Get language instruction
    final languageInstruction = _getLanguageInstruction(language);

    return '''
$basePrompt

## 🎯 Current Review Task

${focusText}You are reviewing the following Dart/Flutter code file. Please provide a comprehensive analysis following the guidelines above.

**File Path**: $filePath
**File Type**: ${fileType.displayName}
**Layer**: ${layer.displayName}

```dart
$code
```

## 📊 Required Review Output

$languageInstruction

Please provide your analysis in the exact format specified in the prompt above, including:

1. **📝 File Summary** - Purpose and architectural role
2. **🏗️ Architecture Analysis** - Layer compliance and pattern usage  
3. **🔍 SOLID Principles Check** - Each principle compliance
4. **📛 Naming Convention Review** - All naming aspects
5. **🐛 Issues Found** - Specific issues with line numbers
6. **🚀 Improvement Suggestions** - Actionable recommendations
7. **✅ Positive Aspects** - What's done well
8. **📈 Overall Rating** - Detailed scoring breakdown
9. **🎯 Priority Actions** - Categorized action items

Focus on Clean Architecture compliance, SOLID principles, and project-specific patterns as documented.
''';
  }

  /// Build batch review prompt for multiple files
  static Future<String> buildBatchReviewPrompt({
    required Map<String, String> filesContent,
    List<String> focusAreas = const [],
    String language = 'en',
  }) async {
    final basePrompt = await loadReviewPrompt();
    final focusText = focusAreas.isNotEmpty
        ? 'Focus specifically on: ${focusAreas.join(', ')}. '
        : '';

    // Get language instruction
    final languageInstruction = _getLanguageInstruction(language);

    final buffer = StringBuffer();
    buffer.writeln(basePrompt);
    buffer.writeln();
    buffer.writeln('## 🎯 Batch Review Task');
    buffer.writeln();
    buffer.writeln(
      '${focusText}You are reviewing multiple Dart/Flutter files in a batch. Please provide analysis for each file following the guidelines above.',
    );
    buffer.writeln();
    buffer.writeln(languageInstruction);
    buffer.writeln();

    // Add each file
    filesContent.forEach((filePath, content) {
      final fileType = FileAnalyzer.getFileType(filePath);
      final layer = FileAnalyzer.getArchitectureLayer(filePath);

      buffer.writeln('### File: $filePath');
      buffer.writeln('**Type**: ${fileType.displayName}');
      buffer.writeln('**Layer**: ${layer.displayName}');
      buffer.writeln();
      buffer.writeln('```dart');
      buffer.writeln(content);
      buffer.writeln('```');
      buffer.writeln();
    });

    buffer.writeln('## 📊 Required Batch Review Output');
    buffer.writeln();
    buffer.writeln('For each file, provide:');
    buffer.writeln('1. **📝 File Summary** with architectural role');
    buffer.writeln('2. **🐛 Critical Issues** with line numbers');
    buffer.writeln('3. **🚀 Key Improvements** needed');
    buffer.writeln('4. **📈 Quick Rating** (1-10 overall score)');
    buffer.writeln();
    buffer.writeln('Then provide an overall batch summary with:');
    buffer.writeln('- **🎯 Common Patterns** found across files');
    buffer.writeln('- **⚠️ Systemic Issues** affecting multiple files');
    buffer.writeln('- **🏆 Best Practices** observed');
    buffer.writeln('- **📋 Action Plan** prioritized by impact');

    return buffer.toString();
  }

  /// Get language instruction for AI
  static String _getLanguageInstruction(String language) {
    switch (language) {
      case 'vi':
        return '''
**🌐 NGÔN NGỮ: Viết toàn bộ phân tích bằng TIẾNG VIỆT.**

**⚠️ CHỈ BÁO CÁO VẤN ĐỀ THỰC SỰ:**
- Security vulnerabilities
- Performance issues nghiêm trọng
- Architecture violations rõ ràng
- Logic bugs có thể gây crash
- Memory/resource leaks

**KHÔNG báo cáo:**
- Private constructors trong constants (đây là pattern chuẩn)
- Generated files formatting
- Library declarations (optional trong Dart)
- Platform checks (cần thiết)
- Style preferences nhỏ

**Giữ nguyên:** Tên code, technical terms, scores (X/10)
''';
      case 'ja':
        return '''
**🌐 言語: 全ての分析を日本語で書いてください。**

**⚠️ 本当に重要な問題のみ報告:**
- セキュリティ脆弱性
- 深刻なパフォーマンス問題
- アーキテクチャ違反
- クラッシュの原因となるバグ
- メモリ/リソースリーク

**報告しない:**
- Constants内のprivate constructors (標準パターン)
- Generated filesのフォーマット
- Library declarations (Dartではオプション)
- Platform checks (必要)
- 小さなスタイル設定

**そのまま:** コード名、技術用語、スコア (X/10)
''';
      case 'ko':
        return '''
**🌐 언어: 모든 분석을 한국어로 작성해주세요.**

**⚠️ 정말 중요한 문제만 보고:**
- 보안 취약점
- 심각한 성능 문제
- 아키텍처 위반
- 크래시 유발 버그
- 메모리/리소스 누수

**보고하지 않음:**
- Constants의 private constructors (표준 패턴)
- Generated files 포맷팅
- Library declarations (Dart에서 선택사항)
- Platform checks (필요함)
- 사소한 스타일 선호도

**유지:** 코드명, 기술 용어, 점수 (X/10)
''';
      case 'zh':
        return '''
**🌐 语言：请用中文编写所有分析。**

**⚠️ 仅报告真正重要的问题:**
- 安全漏洞
- 严重性能问题
- 架构违规
- 可能导致崩溃的错误
- 内存/资源泄漏

**不要报告:**
- Constants中的private constructors (标准模式)
- Generated files格式
- Library declarations (Dart中可选)
- Platform checks (必需)
- 小的样式偏好

**保持:** 代码名称、技术术语、分数 (X/10)
''';
      case 'fr':
        return '''
**🌐 LANGUE: Veuillez rédiger toute l'analyse en FRANÇAIS.**

**⚠️ Signaler uniquement les problèmes vraiment importants:**
- Vulnérabilités de sécurité
- Problèmes de performance graves
- Violations d'architecture
- Bugs pouvant causer des crashs
- Fuites mémoire/ressources

**Ne pas signaler:**
- Private constructors dans constants (pattern standard)
- Formatage des generated files
- Library declarations (optionnel en Dart)
- Platform checks (nécessaires)
- Petites préférences de style

**Conserver:** Noms de code, termes techniques, scores (X/10)
''';
      case 'de':
        return '''
**🌐 SPRACHE: Bitte schreiben Sie die gesamte Analyse auf DEUTSCH.**

**⚠️ Nur wirklich wichtige Probleme melden:**
- Sicherheitslücken
- Schwerwiegende Leistungsprobleme
- Architekturverstöße
- Fehler, die Abstürze verursachen können
- Speicher-/Ressourcenlecks

**Nicht melden:**
- Private constructors in constants (Standardmuster)
- Formatierung von generated files
- Library declarations (optional in Dart)
- Platform checks (notwendig)
- Kleine Stilpräferenzen

**Beibehalten:** Code-Namen, technische Begriffe, Bewertungen (X/10)
''';
      case 'es':
        return '''
**🌐 IDIOMA: Por favor escriba todo el análisis en ESPAÑOL.**

**⚠️ Informar solo problemas realmente importantes:**
- Vulnerabilidades de seguridad
- Problemas graves de rendimiento
- Violaciones de arquitectura
- Errores que pueden causar fallos
- Fugas de memoria/recursos

**No informar:**
- Private constructors en constants (patrón estándar)
- Formato de generated files
- Library declarations (opcional en Dart)
- Platform checks (necesarios)
- Pequeñas preferencias de estilo

**Mantener:** Nombres de código, términos técnicos, puntuaciones (X/10)
''';
      default:
        return '''
**🌐 LANGUAGE: Write the entire analysis in ENGLISH.**

**⚠️ REPORT ONLY REAL ISSUES:**
- Security vulnerabilities
- Serious performance problems
- Clear architecture violations
- Bugs that could cause crashes
- Memory/resource leaks

**DO NOT REPORT:**
- Private constructors in constants (standard pattern)
- Generated files formatting
- Library declarations (optional in Dart)
- Platform checks (necessary)
- Minor style preferences

**Keep as-is:** Code names, technical terms, scores (X/10)
''';
    }
  }

  /// Get fallback prompt if file doesn't exist
  static String _getFallbackPrompt() {
    return '''
# 🤖 Code Review Prompt for Flutter Clean Architecture

You are an expert Dart/Flutter code reviewer specializing in Clean Architecture patterns.
Please review the code following SOLID principles and Flutter best practices.

## 🔍 Review Focus Areas

1. **Architecture Compliance** - Clean Architecture layers and patterns
2. **SOLID Principles** - Single Responsibility, Open/Closed, etc.
3. **Naming Conventions** - Consistent and descriptive naming
4. **Performance** - Efficient code and resource usage
5. **Security** - Secure coding practices
6. **Flutter Best Practices** - Framework-specific optimizations
7. **Code Quality** - Maintainability and readability
8. **Static Analysis** - Must pass flutter analyze --fatal-infos with zero errors/warnings

## 📊 Required Output Format

Provide structured analysis with specific issues, suggestions, and ratings.
''';
  }
}
