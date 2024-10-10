import { defineConfig } from "vitepress";
import {
  cubeOutlineIcon,
  cube02Icon,
  cube01Icon,
  barChartSquare02Icon,
  code02Icon,
  dataIcon,
  checkCircleIcon,
  tuistIcon,
  cloudBlank02Icon,
  server04Icon,
} from "./icons.mjs";

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "Rosalind",
  titleTemplate: ":title | Rosalind | Tuist",
  description: "Analyze Apple-generated bundles",
  sitemap: {
    hostname: "https://rosalind.tuist.io",
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "local",
    },
    nav: [
      {
        text: "Changelog",
        link: "https://github.com/tuist/Rosalind/releases",
      },
    ],
    editLink: {
      pattern: "https://github.com/tuist/Rosalind/edit/main/docs/:path",
    },
    sidebar: [
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Quick start ${tuistIcon()}</span>`,
        items: [
          { text: "Why Rosalind?", link: "/" },
          { text: "Add dependency", link: "/quick-start/add-dependency" },
        ],
      },
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">API ${cube01Icon()}</span>`,
        items: [{ text: "Schema", link: "/api/schema" }],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/tuist/tuist" },
      { icon: "x", link: "https://x.com/tuistio" },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
      {
        icon: "slack",
        link: "https://slack.tuist.io",
      },
    ],
    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2024-present Tuist Inc.",
    },
  },
});
