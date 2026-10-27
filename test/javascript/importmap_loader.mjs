// Resolves the bare "quicsilver/*" specifiers the browser gets from importmap-rails, so the same
// source runs unmodified under node --test.

import { pathToFileURL } from "node:url"
import { resolve as resolvePath } from "node:path"

const root = resolvePath(import.meta.dirname, "../../app/javascript")

export function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("quicsilver/")) {
    return { shortCircuit: true, url: pathToFileURL(`${root}/${specifier}.js`).href }
  }

  return nextResolve(specifier, context)
}
