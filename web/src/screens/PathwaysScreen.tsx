import { useState } from "react";
import { Text, View } from "react-native";
import type { Ctx } from "../App";
import { api, type Pathways } from "../api";
import { NetworkGraph } from "../components/NetworkGraph";
import { Button, Check, IdInput, Input } from "../components/ui";
import { s } from "../theme";

export function PathwaysScreen({ ctx }: { ctx: Ctx }) {
  const [target, setTarget] = useState("");
  const [sources, setSources] = useState("");
  const [fluxOnly, setFluxOnly] = useState(false);
  const [result, setResult] = useState<Pathways>();

  const find = (product = target) => {
    if (product.trim()) api.pathways(product.trim(), sources, fluxOnly).then(setResult).catch(ctx.fail);
  };

  const net = result?.network;
  return (
    <View>
      <View style={[s.row, { alignItems: "flex-start", gap: 16 }]}>
        <IdInput value={target} onChange={setTarget} onPick={(id) => { setTarget(id); find(id); }} items={ctx.model.metabolites} placeholder="target product: succ_c" />
        <Input value={sources} onChange={setSources} width={220} placeholder="from (default: medium)" onSubmit={() => find()} />
        <Check label="fba flux only" value={fluxOnly} onChange={setFluxOnly} />
        <Button title="find routes" onPress={() => find()} />
      </View>
      {result && (
        result.routes.length && net ? (
          <>
            <Text style={s.heading}>{result.routes.length} shortest routes from {result.sources.join(", ")}</Text>
            <NetworkGraph
              network={net}
              width={Math.max(480, (net.width ?? 1) * 180)}
              height={Math.max(200, (net.levels ?? 1) * 38 + 30)}
              onNode={ctx.open}
            />
            {result.routes.map((route, i) => (
              <Text key={i} style={[s.mono, { color: "#6e746d", paddingVertical: 2 }]}>
                {i + 1}. {route.metabolites.map((m) => m.id).join(" → ")}  ({route.steps} steps)
              </Text>
            ))}
          </>
        ) : <Text style={[s.muted, { marginTop: 16 }]}>no route to {target} from {result.sources.join(", ") || "the medium"}</Text>
      )}
    </View>
  );
}
