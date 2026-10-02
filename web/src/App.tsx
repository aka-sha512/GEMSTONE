import { useCallback, useEffect, useState } from "react";
import { Platform, Pressable, ScrollView, Text, View } from "react-native";
import { api, fmt, type Fba, type Model } from "./api";
import { Link } from "./components/ui";
import { FbaScreen } from "./screens/FbaScreen";
import { MetabolitesScreen } from "./screens/MetabolitesScreen";
import { PathwaysScreen } from "./screens/PathwaysScreen";
import { ReactionsScreen } from "./screens/ReactionsScreen";
import { colors, s } from "./theme";

const TABS = ["Reactions", "Metabolites", "Pathways", "FBA"] as const;
type Tab = (typeof TABS)[number];

export type Ctx = {
  model: Model;
  fba: Fba | null;
  revision: number;
  runFba: (objective: string, sense: "max" | "min") => Promise<void>;
  setModel: (model: Model) => void;
  open: (kind: "reaction" | "metabolite", id: string) => void;
  fail: (error: unknown) => void;
};

function pickFile(): Promise<File | undefined> {
  return new Promise((resolve) => {
    if (Platform.OS !== "web") return resolve(undefined);
    const input = Object.assign(document.createElement("input"), { type: "file", accept: ".xml,.sbml,.json,.mat" });
    input.onchange = () => resolve(input.files?.[0]);
    input.click();
  });
}

export default function App() {
  const [model, setModelState] = useState<Model | null>(null);
  const [fba, setFba] = useState<Fba | null>(null);
  const [revision, setRevision] = useState(0);
  const [generation, setGeneration] = useState(0);
  const [tab, setTab] = useState<Tab>("Reactions");
  const [focus, setFocus] = useState<{ kind: string; id: string } | null>(null);
  const [error, setError] = useState("");

  const fail = useCallback((e: unknown) => setError(e instanceof Error ? e.message : String(e)), []);
  const refresh = (next: Model, clearFba = true) => {
    setModelState(next);
    if (clearFba) setFba(null);
    setRevision((r) => r + 1);
    setError("");
  };
  const load = (task: Promise<Model>) => task.then((next) => {
     refresh(next); setGeneration((g) => g + 1); 
    }).catch(fail);

  useEffect(() => {
     load(api.model()); 
    }, []);

  if (!model) return <Text style={
    [s.muted, {
     margin: 32 
    }]}>{error || "Loading model…"}</Text>;

  const ctx: Ctx = {
    model, fba, revision, fail,
    setModel: (next) => refresh(next),
    runFba: async (objective, sense) => {
      const result = await api.fba(objective, sense);
      refresh(await api.model(), false);
      setFba(result);
    },
    open: (kind, id) => {
      setTab(kind === "reaction" ? "Reactions" : "Metabolites");
      setFocus({ kind, id });
    },
  };
  const status = model.objective_value === null ? model.fba_status : `${model.objective_reaction} = ${fmt(model.objective_value, 6)}`;
  const screen = (name: Tab, node: React.ReactNode) => <View style={tab === name ? undefined : { display: "none" }}>{node}</View>;

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.bg }} contentContainerStyle={{ padding: 24, maxWidth: 1280, width: "100%", alignSelf: "center" }}>
      <View style={[s.row, { justifyContent: "space-between", rowGap: 6 }]}>
        <Text style={[s.text, { fontSize: 15 }]}>
          <Text style={{ fontWeight: "700" }}>GEM-STONE</Text>
          <Text style={s.muted}>{"   "}{model.name} · {model.reaction_count} reactions · {model.metabolite_count} metabolites · {model.gene_count} genes · FBA: {status}</Text>
        </Text>
        <View style={[s.row, { flexShrink: 1 }]}>
          <Link label="import…" onPress={() => pickFile().then((file) => file && load(api.upload(file)))} />
          {model.examples.map((name) => <Link key={name} label={name} style={{ color: colors.muted }} onPress={() => load(api.example(name))} />)}
        </View>
      </View>

      <View style={[s.row, s.rule, { gap: 24, marginTop: 20 }]}>
        {TABS.map((name) => (
          <Pressable key={name} accessibilityRole="tab" onPress={() => setTab(name)}
            style={{ paddingVertical: 10, borderBottomWidth: 2, borderBottomColor: tab === name ? colors.accent : "transparent" }}>
            <Text style={[s.text, { color: tab === name ? colors.ink : colors.muted, fontWeight: tab === name ? "600" : "400" }]}>{name}</Text>
          </Pressable>
        ))}
      </View>

      {error ? <Text style={[s.muted, { color: colors.flux, marginTop: 12 }]} onPress={() => setError("")}>{error}  ✕</Text> : null}

      <View key={generation} style={{ paddingTop: 20 }}>
        {screen("Reactions", <ReactionsScreen ctx={ctx} focus={focus?.kind === "reaction" ? focus.id : undefined} />)}
        {screen("Metabolites", <MetabolitesScreen ctx={ctx} focus={focus?.kind === "metabolite" ? focus.id : undefined} />)}
        {screen("Pathways", <PathwaysScreen ctx={ctx} />)}
        {screen("FBA", <FbaScreen ctx={ctx} />)}
      </View>
    </ScrollView>
  );
}
