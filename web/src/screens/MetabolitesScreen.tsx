import { useEffect, useState } from "react";
import { Text, View, useWindowDimensions } from "react-native";
import type { Ctx } from "../App";
import { api, fmt, type MetaboliteView, type Role } from "../api";
import { NetworkGraph } from "../components/NetworkGraph";
import { IdInput, Link } from "../components/ui";
import { s } from "../theme";

function Reactions({ title, items, ctx }: { title: string; items: Role[]; ctx: Ctx }) {
  return (
    <View style={{ flexGrow: 1, flexBasis: 320 }}>
      <Text style={s.heading}>{title} ({items.length})</Text>
      {items.map((r) => (
        <Text key={r.id} style={[s.muted, { paddingVertical: 3 }]} numberOfLines={1}>
          <Link label={r.id} onPress={() => ctx.open("reaction", r.id)} />
          {r.rate !== null && r.rate !== 0 ? `  ${fmt(r.rate, 4)}` : ""}  {r.equation}
        </Text>
      ))}
    </View>
  );
}

export function MetabolitesScreen({ ctx, focus }: { ctx: Ctx; focus?: string }) {
  const { width } = useWindowDimensions();
  const first = ctx.model.metabolites.find((m) => m.id === "pyr_c")?.id ?? ctx.model.metabolites[0]?.id ?? "";
  const [text, setText] = useState(first);
  const [id, setId] = useState(first);
  const [view, setView] = useState<MetaboliteView>();

  useEffect(() => { if (focus) { setText(focus); setId(focus); } }, [focus]);
  useEffect(() => {
    if (id) api.metabolite(id).then(setView).catch(ctx.fail);
  }, [id, ctx.revision, ctx.fail]);

  const size = view ? Math.max(420, Math.sqrt(view.network.nodes.length) * 120) : 0;
  return (
    <View>
      <IdInput value={text} onChange={setText} onPick={setId} items={ctx.model.metabolites} placeholder="metabolite: pyr_c" />
      {view && (
        <>
          <Text style={[s.text, { marginTop: 16 }]}>
            <Text style={{ fontWeight: "700" }}>{view.metabolite.name}</Text>  <Text style={s.muted}>{view.metabolite.id} {view.metabolite.formula}</Text>
          </Text>
          <NetworkGraph
            network={view.network}
            width={Math.max(Math.min(width - 48, 1232), size * 1.3)}
            height={size * 0.85}
            onNode={(kind, nodeId) => (kind === "reaction" ? ctx.open("reaction", nodeId) : (setText(nodeId), setId(nodeId)))}
          />
          <View style={{ flexDirection: "row", flexWrap: "wrap", columnGap: 32 }}>
            <Reactions title="produced by" items={view.producers} ctx={ctx} />
            <Reactions title="consumed by" items={view.consumers} ctx={ctx} />
          </View>
        </>
      )}
    </View>
  );
}
