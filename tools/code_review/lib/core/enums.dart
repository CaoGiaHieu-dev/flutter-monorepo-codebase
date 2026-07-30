/// Review mode enumeration
enum ReviewMode { batch, individual }

/// Priority levels for issues
enum IssuePriority { high, medium, low }

/// File types for better categorization
enum FileType {
  page,
  widget,
  provider,
  entity,
  useCase,
  repository,
  repositoryImpl,
  dataSource,
  constants,
  config,
  model,
  parameters,
  dartFile,
}

/// Architecture layers
enum ArchitectureLayer { presentation, domain, data, core, generated, unknown }

extension FileTypeExtension on FileType {
  String get displayName {
    switch (this) {
      case FileType.page:
        return 'Page';
      case FileType.widget:
        return 'Widget';
      case FileType.provider:
        return 'Provider';
      case FileType.entity:
        return 'Entity';
      case FileType.useCase:
        return 'UseCase';
      case FileType.repository:
        return 'Repository Interface';
      case FileType.repositoryImpl:
        return 'Repository Implementation';
      case FileType.dataSource:
        return 'Data Source';
      case FileType.constants:
        return 'Constants';
      case FileType.config:
        return 'Configuration';
      case FileType.model:
        return 'Model';
      case FileType.parameters:
        return 'Parameters';
      case FileType.dartFile:
        return 'Dart File';
    }
  }
}

extension ArchitectureLayerExtension on ArchitectureLayer {
  String get displayName {
    switch (this) {
      case ArchitectureLayer.presentation:
        return 'Presentation Layer';
      case ArchitectureLayer.domain:
        return 'Domain Layer';
      case ArchitectureLayer.data:
        return 'Data Layer';
      case ArchitectureLayer.core:
        return 'Core Layer';
      case ArchitectureLayer.generated:
        return 'Generated Code';
      case ArchitectureLayer.unknown:
        return 'Unknown Layer';
    }
  }
}
