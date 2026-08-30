# Prosemirror
A Dart port of the Prosemirror Typescript implementation.

This project is not affiliated with the official Prosemirror project.

## Package Goal
The goal of this package is to provide Dart/Flutter developers with a robust logical
document structure and editor. The fact that Prosemirror was chosen for this purpose is simply
the result of Prosemirror proving itself to be effective in that regard.

### Prosemirror Benefits
 * Battle tested (but primarily in the browser)
 * DOM-compatible, but not DOM-centric (good for cross-platform uses)
 * Supports undo/redo at its core
 * Supports multiplayer editing at its core

## The Porting Strategy
This package ports Prosemirror by directly porting Typescript tests to Dart, and then those tests
are made to pass with a custom implementation.

This approach should preserve the public API, while giving the package latitude to make
implementation decisions that make sense for Dart.

### Future Consistency
This package will make a reasonable effort to match the public API of the official Prosemirror
project over time.

Caveats:
* This package can't depend on the existence of a DOM.
* If the absence of the DOM lets this package greatly simplify some APIs, it will.
* Dart language details might impact some APIs.

### Packaging
At the time that this package ported Prosemirror, the Prosemirror source code was split into a
number of separate repositories. These boundaries are retained in this package, but rather than
create separate repositories or separate projects, this package uses separate source directories.

For example:
 * `lib/src/model`: Port of the `prosemirror-model` repository.
 * `lib/src/transform`: Port of the `prosemirror-transform` repository.
 * etc

