// After the Mac app updates, an open phone page keeps running the old code, which may not
// understand the new agent's messages (it drops them, so the screen stops changing). Each build
// names its scripts and styles by content hash, so comparing them with the served page tells
// whether this page is out of date.

/** The scripts and stylesheets a page loads, as written in its HTML. */
export function pageAssets(doc: Document): string[] {
  const assets = [
    ...[...doc.querySelectorAll("script[src]")].map((el) => el.getAttribute("src")),
    ...[...doc.querySelectorAll('link[rel="stylesheet"][href]')].map((el) =>
      el.getAttribute("href"),
    ),
  ];
  return assets.filter((src): src is string => src !== null).sort();
}

/**
 * Whether the page served at `path` loads different assets than `current`. Any failure counts
 * as no change, so a flaky network never causes a reload loop.
 */
export async function pageChanged(
  fetchFn: typeof fetch,
  path: string,
  current: readonly string[],
): Promise<boolean> {
  try {
    const response = await fetchFn(path, { cache: "no-store" });
    if (!response.ok) return false;
    const served = pageAssets(new DOMParser().parseFromString(await response.text(), "text/html"));
    if (served.length === 0) return false;
    return served.join("\n") !== current.join("\n");
  } catch {
    return false;
  }
}
