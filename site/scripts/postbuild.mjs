import { copyFileSync } from "node:fs";
import { join } from "node:path";

// Preserve published .html links while the canonical URLs remain extensionless.
for (const route of ["about", "technology", "support", "privacy", "terms"]) {
  copyFileSync(join("out", route, "index.html"), join("out", `${route}.html`));
}
