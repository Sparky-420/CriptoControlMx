/// Boundary marker for the safe UI refactor branch.
///
/// This file is intentionally UI-only. Financial formulas, movement persistence,
/// snapshots and import/export logic must remain outside this layer.
class UiRefactorBoundary {
  static const String scope = 'ui-only';
  static const String mathGuard = 'finance-core-untouched';
}
