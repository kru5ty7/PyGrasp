/**
 * Quartz Visualizer Script
 *
 * Inline `<script>` tags embedded in markdown content are present in the DOM
 * but never executed by the browser. This happens because:
 *   1. Quartz's SPA router uses `micromorph` to morph the page body,
 *      and browsers do not execute scripts inserted via innerHTML / DOM morphing.
 *   2. Even on a cold page load, `rehype-raw` preserves the tags in the HTML
 *      output, but the script content is treated as inert text.
 *
 * This script runs on every `nav` event and manually evaluates the JavaScript
 * found inside visualizer wrapper elements.
 *
 * Strategy: Each visualizer script is an IIFE that registers listeners for
 * `DOMContentLoaded` and `nav`. Since both events have already fired by the
 * time this script runs, we patch the code to replace those event registrations
 * with an immediate call to the init function, then evaluate the result.
 */

function initVisualizers() {
  // Find all script tags inside the article content
  const articleContent = document.querySelector("article") ?? document.body
  const scriptTags = articleContent.querySelectorAll("script")

  for (const script of scriptTags) {
    // Skip empty scripts or already-executed ones
    const code = script.textContent?.trim()
    if (!code || script.dataset.vizExecuted === "true") continue

    // Only process scripts inside known visualizer wrappers
    const wrapper = script.parentElement
    if (!wrapper?.id?.endsWith("-wrap")) continue

    // Mark as executed
    script.dataset.vizExecuted = "true"

    try {
      // Patch the code: replace event listener registrations with immediate calls.
      // The pattern in all visualizer scripts is:
      //   document.addEventListener('DOMContentLoaded', init);
      //   document.addEventListener('nav', init);
      // We replace these with: init();
      // This works because the code is inside an IIFE, so `init` is in scope.
      let patched = code
        .replace(
          /document\.addEventListener\s*\(\s*['"]DOMContentLoaded['"]\s*,\s*(\w+)\s*\)\s*;?/g,
          "$1();",
        )
        .replace(
          /document\.addEventListener\s*\(\s*['"]nav['"]\s*,\s*(\w+)\s*\)\s*;?/g,
          "/* nav listener removed - called directly */",
        )

      const fn = new Function(patched)
      fn()
    } catch (e) {
      console.error(`[Visualizer] Error executing script in #${wrapper.id}:`, e)
    }
  }
}

document.addEventListener("nav", () => {
  // Small delay to ensure the DOM has been fully morphed by micromorph
  setTimeout(initVisualizers, 50)
})
