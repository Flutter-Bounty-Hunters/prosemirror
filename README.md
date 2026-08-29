# Prosemirror
A Dart port of the Prosemirror Typescript implementation.

This project is not affiliated with the official Prosemirror project.

## Package Goal
The goal of this package is primarily to provide Dart/Flutter developers with a robust logical
document structure and editor. The fact that Prosemirror was chosen for this purpose is simply
the result of Prosemirror proving itself to be effective in that regard.

## How similar is this package to Prosemirror?
This package aims to closely resemble the Prosemirror Typescript implementation.

However, Prosemirror is unabashedly a product of the browser-tech world (HTML, JS, TS, CSS, DOM).
As a result, some capabilities might be left out of this package, such as DOM-centric behaviors
that mean nothing in Dart. Similarly, new behaviors might be added to handle the absence of the
DOM.