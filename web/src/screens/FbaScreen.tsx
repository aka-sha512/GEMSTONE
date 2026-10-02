import { useState } from "react";
import { FlatList, Text, View } from "react-native";
import type { Ctx } from "../App";
import { fmt } from "../api";
import { Button, IdInput, Input, Link } from "../components/ui";
import { colors, s } from "../theme";

export function FbaScreen({ ctx }: { ctx: Ctx }) {
  const [objective, setObjective] = useState(ctx.model.objective_reaction);
  const [filter, setFilter] = useState("");

  const run = () => ctx.runFba(objective.trim()).catch(ctx.fail);

  const fluxes = Object.entries(ctx.fba?.fluxes ?? {})
    .filter(([id, v]) => v !== 0 && id.toLowerCase().includes(filter.toLowerCase()))
    .sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
  const max = Math.max(...fluxes.map(([, v]) => Math.abs(v)), 1e-12);

  return (
    <View>
      <View style={[s.row, { alignItems: "flex-start", gap: 16 }]}>
        <IdInput value={objective} onChange={setObjective} onPick={setObjective} items={ctx.model.reactions} placeholder="objective reaction" />
        <Button title="run fba" onPress={run} />
      </View>

      {ctx.fba && (
        <>
          <Text style={[s.text, { fontSize: 22, marginTop: 28 }]}>
            {fmt(ctx.fba.objective_value, 6)}  <Text style={s.muted}>{ctx.fba.status} · {fluxes.length} active reactions</Text>
          </Text>
          <View style={{ marginTop: 12 }}>
            <Input value={filter} onChange={setFilter} placeholder="filter fluxes" width={220} />
          </View>
          <FlatList
            style={{ maxHeight: 560, marginTop: 8 }}
            data={fluxes}
            keyExtractor={([id]) => id}
            renderItem={({ item: [id, v] }) => (
              <View style={[s.row, { paddingVertical: 4, flexWrap: "nowrap" }]}>
                <Link label={id} onPress={() => ctx.open("reaction", id)} style={{ width: 200 }} />
                <Text style={[s.mono, { width: 90, textAlign: "right" }]}>{fmt(v)}</Text>
                <View style={{ flex: 1, height: 4, flexDirection: "row" }}>
                  <View style={{ flex: 1, alignItems: "flex-end" }}>{v < 0 && <View style={{ width: `${(-v / max) * 100}%`, height: 4, backgroundColor: colors.idle }} />}</View>
                  <View style={{ flex: 1 }}>{v > 0 && <View style={{ width: `${(v / max) * 100}%`, height: 4, backgroundColor: colors.flux }} />}</View>
                </View>
              </View>
            )}
          />
        </>
      )}
    </View>
  );
}
