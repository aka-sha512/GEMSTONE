// client for the julia json api (src/server.jl)

export type Item = { id: string; name: string };

export type Model = {
  id: string;
  name: string;
  reaction_count: number;
  metabolite_count: number;
  gene_count: number;
  objective_reaction: string;
  fba_status: string;
  objective_value: number | null;
  metabolites: Item[];
  reactions: Item[];
  examples: string[];
};

export type Reaction = Item & {
  equation: string;
  lower_bound: number;
  upper_bound: number;
  gpr: string;
  genes: Item[];
  metabolites: (Item & { coefficient: number })[];
  flux: number | null;
};

export type Network = {
  nodes: { key: string; id: string; kind: "metabolite" | "reaction"; label: string; role: string; x: number; y: number; active?: boolean }[];
  edges: { source: string; target: string; active: boolean; reversible: boolean }[];
};

export type Role = Item & { equation: string; rate: number | null };
export type MetaboliteView = { metabolite: Item & { formula: string }; producers: Role[]; consumers: Role[]; network: Network };
export type Pathways = { routes: { source: string; steps: number; metabolites: Item[]; reactions: Item[] }[]; sources: string[]; network: Network & { width?: number; levels?: number } };
export type Fba = { status: string; objective_value: number | null; fluxes: Record<string, number> };

async function call<T>(url: string, body?: unknown): Promise<T> {
  const init = body === undefined ? undefined
    : body instanceof ArrayBuffer ? { method: "POST", body }
    : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
  const response = await fetch(url, init);
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error ?? `request failed: ${response.status}`);
  return payload as T;
}

const q = encodeURIComponent;

export const api = {
  model: () => call<Model>("/api/model"),
  example: (name: string) => call<Model>(`/api/example?name=${q(name)}`, {}),
  upload: async (file: File) => call<Model>(`/api/upload?filename=${q(file.name)}`, await file.arrayBuffer()),
  search: (text: string) => call<{ results: Item[] }>(`/api/search?q=${q(text)}`),
  reaction: (id: string) => call<Reaction>(`/api/reaction?id=${q(id)}`),
  metabolite: (id: string) => call<MetaboliteView>(`/api/metabolite?id=${q(id)}`),
  pathways: (target: string, sources: string, fluxOnly: boolean) =>
    call<Pathways>(`/api/pathways?target=${q(target)}&sources=${q(sources)}&flux_only=${fluxOnly}`),
  fba: (objective: string) => call<Fba>("/api/fba", { objective }),
};

export const fmt = (x: number | null | undefined, digits = 5) =>
  x === null || x === undefined ? "—" : Math.abs(x) < 1e-9 ? "0" : String(Number(x.toPrecision(digits)));
