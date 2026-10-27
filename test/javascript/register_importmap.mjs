// Entry point for `node --import`: installs the importmap resolver hook.

import { register } from "node:module"

register("./importmap_loader.mjs", import.meta.url)
