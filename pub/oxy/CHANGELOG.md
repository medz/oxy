## 0.0.2

### Breaking Changes

- **AbortController removed**: `AbortController` class has been removed. Use `AbortSignal()` constructor directly instead.
- **AbortSignal API simplified**: `AbortSignal` now has a public constructor and includes the `abort()` method directly.

### Changes

- Removed `AbortController` class - no longer needed as `AbortSignal` can be created directly
- Made `AbortSignal.abort()` method public - signals can now abort themselves
- Removed `meta` dependency - no longer using `@internal` annotations
- Updated `AdapterRequest` to use `AbortSignal()` instead of `AbortController().signal`

### Migration Guide

**Before (v0.0.1):**
```dart
final controller = AbortController();
final signal = controller.signal;

// Abort the signal
controller.abort('reason');
```

**After (v0.0.2):**
```dart
final signal = AbortSignal();

// Abort the signal directly
signal.abort('reason');
```

## 0.0.1

First version
