# Rosalind

# Rosalind

[Rosalind Franklin](https://en.wikipedia.org/wiki/Rosalind_Franklin) was a pioneering scientist whose X-ray crystallography work revealed the fundamental structure of DNA, transforming our understanding of life itself. In a similar way, modern applications across platforms—iOS, Android, and React Native—have complex internal architectures that, when properly understood, can be optimized for performance, efficiency, and user experience.

Our tool, Rosalind, analyzes application bundles to uncover these hidden structures, providing developers with clear, actionable insights about their code, dependencies, resources, and overall composition. By making the invisible visible, Rosalind empowers development teams to make informed decisions when refining their applications.

> [!NOTE]
> Inspired by Franklin's commitment to scientific discovery, we've made Rosalind open-source under the MIT license. We believe that understanding application architecture should be accessible to all developers, regardless of platform or team size, fostering a more collaborative and innovative development community.

> [!WARNING]
> While Rosalind can be built on Linux systems, it currently can only be run on macOS due to a runtime dependency on the macOS-only `assetutil` CLI tool. This is something we'd like to address in the future.

Rosalind currently provides comprehensive analysis of Xcode-built application artifacts, with planned support for Android and React Native platforms in our development roadmap. Our vision is to offer a unified approach to understanding the DNA of your applications across all major app development ecosystems.

## Development

### Set up

1. Clone the repository: `git clone https://github.com/tuist/rosalind`.
2. Install system dependencies: `mise install`.
3. Install project dependencies: `mise run install`.
4. Build the project: `mise run build`.
