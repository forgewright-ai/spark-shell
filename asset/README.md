# spark-shell identity assets

The current spark-shell symbol is a solid diamond nested inside a solid forward chevron. It replaces the earlier S used here; spark's separate identity is unchanged.

`favicon.svg` and `logo.svg` use light ink (`#E9E7DC`) for dark grounds. The `-light` variants use dark ink (`#080A0F`) for light grounds. All four SVGs use the same two canonical paths and tight `0.6 0.6 14.8 14.8` viewBox.

spark-bar loads `favicon-{16,19,22,26}.png` or `favicon-light-{16,19,22,26}.png` before using an SVG for larger sizes. Keep both complete PNG sets synchronized with their SVGs. These are transparent RGBA exports of the approved geometry, with no background plate or extra clear-space padding. The bar chooses dark/light files; it does not recolor artwork to the theme accent.

Larger rasterizations are cached under `$XDG_RUNTIME_DIR/spark-shell-bar.icons/` and invalidated when the source SVG is newer. Install replacement SVGs with a fresh modification time and restart the bar normally. Verify both ground variants and a size above 26 px after installation.

Source: spark-shell brand asset package 1.0.0, 14 November 2026. Full wordmark, favicon and animated exports belong to that package; the status bar uses the nested mark only.
