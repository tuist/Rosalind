---
title: Schema
titleTemplate: ':title | API | Rosalind | Tuist'
description: "Learn about the schema of the results of the analysis."
---

# Schema

> [!TIP]
> We haven't reached 1.0 yet, so breaking changes are possible.

Rosalind returns an instance of `RosalindReport`, a type that can be encoded to [JSON](https://www.w3schools.com/whatis/whatis_json.asp) thanks to its conformance to the `Codable` protocol.

`RosalindReport` creates a hierarchical tree structure where each node represents either a file or a directory, along with corresponding metadata.

### Attributes

Each node in the tree includes these attributes:

- **artifactType:** Categorizes the artifact as an `app`, `directory`, or `file`.
- **path:** Specifies the artifact's path relative to the project root.
- **size:** Records the artifact's size in bytes.
- **shasum:** Provides a SHA-256 checksum of the artifact for integrity verification.
- **children:** Contains an array of child artifacts (present only if the node is a directory).

> [!NOTE]
> In future updates, we plan to expand the `artifactType` enumeration to include more specific categories that better describe various artifacts.
