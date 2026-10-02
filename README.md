# GEM-STONE

A local GUI for exploring **genome-scale metabolic models (GEMs)** without writing code. Import a
model, search reactions, inspect metabolites and their neighbourhood, trace pathways from substrates
to a product, and run flux balance analysis (FBA).

All analysis runs in Julia. The GUI is written in **React Native** and runs in the browser through
[react-native-web](https://necolas.github.io/react-native-web/). The Julia server serves the built UI, so
running the app needs only Julia.

![Metabolite network](docs/screenshots/2-metabolite-network.png)

## Features

| Function | What you get |
|---|---|
| **Reaction search & inspection** | One search box matches reaction ID or name, metabolites and genes (ID or name), with exact ID hits ranked first. Shows the equation (each metabolite is a link), bounds, flux from the last FBA, genes and the GPR rule. |
| **Metabolite analysis** | Producing and consuming reactions under current bounds, with per-reaction rates after FBA, and a local network graph. Currency metabolites (H⁺, H₂O, ATP, NAD(P)H…) are hidden and large models are capped, so hubs stay readable. Click nodes to move around the network. |
| **Product pathways** | Shortest routes (k-shortest paths) to a target product, from the model's medium or from precursors you list. Uses carbon-matched substrate→product pairs and skips currency metabolites, drawn as a top-to-bottom pathway graph. A toggle follows only reactions that carry FBA flux. |
| **Flux balance analysis** | Choose any objective reaction and maximize it, then view the objective value and the nonzero fluxes, which you can filter. Bounds come from the model file and are read-only. |

Supported formats: **SBML** (`.xml`/`.sbml`, FBC package), **COBRA JSON** (`.json`), **COBRA MAT** (`.mat`).
BiGG SBML's `R_`/`M_`/`G_` ID prefixes are removed so IDs match across formats.

## Setup

Requires **Julia** (developed and tested with 1.13.1) and a web browser. The first run downloads packages.
The built UI is committed in `public/`, so Node.js is only needed to change the front end (see below).

```sh
git clone <this repo> GEM-STONE && cd GEM-STONE
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

`Project.toml` and `Manifest.toml` pin the exact environment.

## Run

```sh
julia --project=. run.jl                       # loads examples/e_coli_core.json
julia --project=. run.jl path/to/model.xml     # or start with your own model
PORT=8001 julia --project=. run.jl             # different port
```

Then open <http://127.0.0.1:8000>. The server listens only on localhost, and uploaded models stay on this machine.
Use **import...** or one of the example names in the header to switch models.


## Front end development (React Native for Web)

The UI source is in `web/`: React Native components (`View`, `Text`, `TextInput`, `Pressable`,
`FlatList`, `react-native-svg`) written in TypeScript and bundled by Vite. Vite resolves
`react-native` to `react-native-web`. Requires Node.js (tested with 26) and [pnpm](https://pnpm.io) (tested with 12.8).

```sh
cd web
pnpm install
pnpm dev            # hot-reloading UI on http://localhost:5173; /api is proxied to the Julia server on :8000
pnpm build          # type-check, then write the production bundle to ../public (served by Julia)
pnpm e2e            # headless-Firefox UI test with real clicks/typing (server must be running)
pnpm screenshots    # same test, also saving docs/screenshots
```

For `pnpm dev`, start the API first in another terminal with `julia --project=. run.jl`.
`PORT=8765 pnpm e2e` targets a server on a different port. The test resets the server to
`e_coli_core.json` first.

## Use from the REPL

The GUI calls the same functions you can use from the REPL:

```julia
using GEMStone
m = load_model("examples/e_coli_core.xml")
run_fba!(m, "BIOMASS_Ecoli_core_w_GAM").objective_value     # 0.8739
search_reactions(m, "pfkA"; field="gene")                     # PFK
pathway_routes(m, "succ_c").routes[1].metabolites
run_fba!(m, "ATPM").objective_value                          # any reaction as objective
```

## Example models (`examples/`)

| File | Description |
|---|---|
| `e_coli_core.json` / `.xml` / `.mat` | *E. coli* core metabolism (95 reactions, 72 metabolites, 137 genes) from [BiGG](http://bigg.ucsd.edu/models/e_coli_core), in all three formats. Aerobic glucose growth = 0.874 h⁻¹. |
| `toy_glucose.xml` | 5-reaction teaching model (glucose → pyruvate → biomass). Small enough to check by hand. |

Larger models, such as [iML1515](http://bigg.ucsd.edu/models/iML1515) (2,712 reactions), Recon3D or
[Human-GEM](https://github.com/SysBioChalmers/Human-GEM), can be imported the same way. iML1515 loads,
solves and draws within a second.

## Project layout

```
src/GEMStone.jl   module entry
src/model.jl      model import (AbstractFBCModels), data structures, equations
src/search.jl     ranked reaction search
src/network.jl    currency metabolites, metabolite analysis, local network + layout
src/pathway.jl    carbon-matched metabolite graph, k-shortest routes, pathway layout
src/fba.jl        FBA linear program (JuMP + HiGHS), bound editing
src/server.jl     HTTP/JSON API + static files from public/
web/              React Native (react-native-web) UI source: App.tsx, screens/, components/
public/           built UI (generated by `pnpm build`; committed so Julia alone can run the app)
run.jl            launcher
```