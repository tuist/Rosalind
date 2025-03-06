---
title: Schema
titleTemplate: ':title | Rosalind | Rosalind | Tuist'
description: "Learn how to use Rosalind to analyze your build artifacts."
---

# Rosalind

The interface with Rosalind is through an instance of the `Rosalind` struct.
It exposes a function, `analyze` that takes a path and returns a [report](/api/schema).

```swift
let report = Rosalind().analyze(path: try AbsolutePath(validating: "/path/to/MyApp.app"))
```

Since `RosalindReport` conforms to `Coddable`, you can serialize it into a JSON `Data` instance:

```swift
let jsonEncoder = JSONEncoder()
jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let reportData = try jsonEncoder.encode(value)
```
