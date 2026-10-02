import { useEffect, useState } from "react";
import { FlatList, Pressable, Text, View } from "react-native";
import type { Ctx } from "../App";
import { api, fmt, type Item, type Reaction } from "../api";
import { Input, Link } from "../components/ui";
import { colors, s } from "../theme";

export function ReactionsScreen({ ctx, focus }: { ctx: Ctx; focus?: string }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Item[]>([]);
  const [selected, setSelected] = useState<string>();
  const [reaction, setReaction] = useState<Reaction>();

  useEffect(() => { if (focus) { setQuery(focus); setSelected(focus); } }, [focus]);

  useEffect(() => {
    let live = true;
    api.search(query).then(({ results }) => {
      if (!live) return;
      setResults(results);
      setSelected((current) => (current && results.some((r) => r.id === current) ? current : results[0]?.id));
    }).catch(ctx.fail);
    return () => { live = false; };
  }, [query, ctx.revision, ctx.fail]);

  useEffect(() => {
    if (selected) api.reaction(selected).then(setReaction).catch(ctx.fail);
  }, [selected, ctx.revision, ctx.fail]);

  return (
    <View>
      <Input value={query} onChange={setQuery} placeholder="search reactions, metabolites or genes: PFK, pyruvate, pfkA" />
      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 32, marginTop: 16 }}>
        <FlatList
          style={{ flexGrow: 1, flexBasis: 260, maxHeight: 520 }}
          data={results}
          keyExtractor={(r) => r.id}
          ListEmptyComponent={<Text style={s.muted}>no matches</Text>}
          renderItem={({ item }) => (
            <Pressable onPress={() => setSelected(item.id)} style={{ paddingVertical: 6 }}>
              <Text style={[s.mono, item.id === selected && { color: colors.accent, fontWeight: "700" }]}>
                {item.id} <Text style={s.muted}>{item.name}</Text>
              </Text>
            </Pressable>
          )}
        />
        <View style={{ flexGrow: 2, flexBasis: 420 }}>{reaction && <Details r={reaction} ctx={ctx} />}</View>
      </View>
    </View>
  );
}

function Details({ r, ctx }: { r: Reaction; ctx: Ctx }) {
  const arrow = r.equation.match(/<=>|-->|<--|-x-/)?.[0] ?? "-->";
  const side = (sign: number) => r.metabolites.filter((m) => Math.sign(m.coefficient) === sign).map((m, i) => (
    <Text key={m.id}>
      {i > 0 && " + "}
      {Math.abs(m.coefficient) !== 1 && `${fmt(Math.abs(m.coefficient), 4)} `}
      <Link label={m.id} onPress={() => ctx.open("metabolite", m.id)} />
    </Text>
  ));
  const genes = r.genes.map((g) => (g.name && g.name !== g.id ? `${g.id} (${g.name})` : g.id)).join(", ");
  return (
    <View style={{ gap: 10 }}>
      <Text style={[s.text, { fontSize: 18 }]}><Text style={{ fontWeight: "700" }}>{r.id}</Text>  <Text style={s.muted}>{r.name}</Text></Text>
      <Text style={[s.mono, { lineHeight: 20 }]}>{side(-1)} {arrow} {side(1)}</Text>
      <Text style={s.muted}>
        bounds [{fmt(r.lower_bound)}, {fmt(r.upper_bound)}] · flux {r.flux === null ? "not solved" : fmt(r.flux)}
      </Text>
      <Text style={s.muted}>genes {genes || "none"}</Text>
      {r.gpr ? <Text style={[s.mono, { color: colors.muted }]}>{r.gpr}</Text> : null}
    </View>
  );
}
