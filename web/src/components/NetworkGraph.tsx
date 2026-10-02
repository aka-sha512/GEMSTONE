import { useId } from "react";
import { ScrollView } from "react-native";
import Svg, { Defs, G, Line, Marker, Path, Rect, Text as SvgText } from "react-native-svg";
import type { Network } from "../api";
import { colors } from "../theme";

const PAD = 60;
const label = (text: string) => (text.length > 18 ? `${text.slice(0, 17)}…` : text);

export function NetworkGraph({ network, width, height, onNode }: {
  network: Network;
  width: number;
  height: number;
  onNode: (kind: "metabolite" | "reaction", id: string) => void;
}) {
  const arrow = useId().replace(/:/g, ""); // marker ids must be unique on the page
  const box = Object.fromEntries(network.nodes.map((n) => [n.key, {
    x: PAD + n.x * (width - 2 * PAD),
    y: PAD / 2 + n.y * (height - PAD),
    w: label(n.label).length * 6.6 + 16,
    h: 20,
  }]));

    const trim = (a: (typeof box)[string], b: (typeof box)[string]) => {
    const dx = b.x - a.x, dy = b.y - a.y;
    const t = Math.min(dx ? (b.w / 2 + 3) / Math.abs(dx) : 1, dy ? (b.h / 2 + 3) / Math.abs(dy) : 1, 1);
    return [b.x - dx * t, b.y - dy * t];
  };

  return (
    <ScrollView horizontal contentContainerStyle={{ flexGrow: 1, justifyContent: "center" }}>
      <Svg width={width} height={height}>
        <Defs>
          {[["on", colors.flux], ["off", colors.idle]].map(([id, fill]) => (
            <Marker key={id} id={`${arrow}-${id}`} markerUnits="userSpaceOnUse" markerWidth={8} markerHeight={8} refX={7} refY={4} orient="auto">
              <Path d="M0,0 L8,4 L0,8 z" fill={fill} />
            </Marker>
          ))}
        </Defs>
        {network.edges.map((e, i) => {
          const a = box[e.source], b = box[e.target];
          const [x1, y1] = trim(b, a), [x2, y2] = trim(a, b);
          return (
            <Line key={i} x1={x1} y1={y1} x2={x2} y2={y2}
              stroke={e.active ? colors.flux : colors.idle} strokeWidth={e.active ? 1.8 : 1}
              strokeDasharray={e.reversible ? "4 4" : undefined}
              markerEnd={e.reversible ? undefined : `url(#${arrow}-${e.active ? "on" : "off"})`} />
          );
        })}
        {network.nodes.map((n) => {
          const { x, y, w, h } = box[n.key];
          const reaction = n.kind === "reaction";
          const strong = !reaction && n.role !== "metabolite";
          const fill = reaction ? (n.active ? colors.fluxPale : "white") : strong ? colors.accent : colors.accentPale;
          return (
            <G key={n.key} onPress={() => onNode(n.kind, n.id)}>
              <Rect x={x - w / 2} y={y - h / 2} width={w} height={h} rx={reaction ? 3 : 10}
                fill={fill} stroke={reaction ? colors.flux : colors.accent} strokeWidth={0.8} />
              <SvgText x={x} y={y + 4} textAnchor="middle" fontSize={11} fontFamily="monospace"
                fill={strong ? "white" : colors.ink} pointerEvents="none">{label(n.label)}</SvgText>
            </G>
          );
        })}
      </Svg>
    </ScrollView>
  );
}
