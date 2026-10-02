import { Pressable, Text, TextInput, View, type StyleProp, type TextStyle } from "react-native";
import type { Item } from "../api";
import { colors, s } from "../theme";

export function Button({ title, onPress, quiet }: { title: string; onPress: () => void; quiet?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 6, backgroundColor: quiet ? "transparent" : colors.accent }}
    >
      <Text style={[s.text, { color: quiet ? colors.accent : "white", fontWeight: "600" }]}>{title}</Text>
    </Pressable>
  );
}

export function Input({ value, onChange, placeholder, width, onSubmit }: {
  value: string;
  onChange: (text: string) => void;
  placeholder?: string;
  width?: number;
  onSubmit?: () => void;
}) {
  return (
    <TextInput
      value={value}
      onChangeText={onChange}
      onSubmitEditing={onSubmit}
      placeholder={placeholder}
      placeholderTextColor={colors.idle}
      spellCheck={false}
      autoCapitalize="none"
      style={[s.text, { width, flexGrow: width ? 0 : 1, minWidth: width ?? 160, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: colors.line }]}
    />
  );
}

export function Check({ label, value, onChange }: { label: string; value: boolean; onChange: (value: boolean) => void }) {
  return (
    <Pressable accessibilityRole="checkbox" aria-checked={value} onPress={() => onChange(!value)} style={[s.row, { gap: 6, paddingVertical: 8 }]}>
      <View style={{ width: 13, height: 13, borderRadius: 3, borderWidth: 1, borderColor: colors.accent, backgroundColor: value ? colors.accent : "transparent" }} />
      <Text style={s.muted}>{label}</Text>
    </Pressable>
  );
}

export const Link = ({ label, onPress, style }: { label: string; onPress: () => void; style?: StyleProp<TextStyle> }) => (
  <Text accessibilityRole="link" onPress={onPress} style={[s.link, style]}>{label}</Text>
);

// text input listing up to six matching ids underneath (react native has no <datalist>)
export function IdInput({ value, onChange, onPick, items, placeholder }: {
  value: string;
  onChange: (text: string) => void;
  onPick: (id: string) => void;
  items: Item[];
  placeholder?: string;
}) {
  const needle = value.trim().toLowerCase();
  const exact = items.some((item) => item.id === value);
  const matches = needle && !exact
    ? items.filter((item) => item.id.toLowerCase().includes(needle) || item.name.toLowerCase().includes(needle)).slice(0, 6)
    : [];
  return (
    <View style={{ flexGrow: 1, minWidth: 200 }}>
      <Input value={value} onChange={onChange} placeholder={placeholder} onSubmit={() => onPick(matches[0]?.id ?? value.trim())} />
      {matches.length > 0 && (
        <View style={[s.row, { marginTop: 6, gap: 14 }]}>
          {matches.map((item) => <Link key={item.id} label={item.id} onPress={() => { onChange(item.id); onPick(item.id); }} />)}
        </View>
      )}
    </View>
  );
}
