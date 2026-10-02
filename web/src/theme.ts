import { StyleSheet } from "react-native";

export const colors = {
  bg: "#fbfbf8",
  ink: "#1f251f",
  muted: "#6e746d",
  line: "#e3e6df",
  accent: "#25684c",
  accentPale: "#e8f0ea",
  flux: "#d36c39",
  fluxPale: "#f8ebe2",
  idle: "#a3aca2",
};

const mono = '"IBM Plex Mono", ui-monospace, Consolas, monospace';
const sans = '"Inter", "Segoe UI", system-ui, sans-serif';

export const s = StyleSheet.create({
  text: { fontFamily: sans, fontSize: 14, color: colors.ink },
  muted: { fontFamily: sans, fontSize: 13, color: colors.muted },
  mono: { fontFamily: mono, fontSize: 12.5, color: colors.ink },
  heading: { fontFamily: sans, fontSize: 12, fontWeight: "600", color: colors.muted, marginTop: 24, marginBottom: 8 },
  link: { fontFamily: mono, fontSize: 12.5, color: colors.accent },
  row: { flexDirection: "row", alignItems: "center", flexWrap: "wrap", gap: 10 },
  rule: { borderBottomWidth: 1, borderBottomColor: colors.line },
});
