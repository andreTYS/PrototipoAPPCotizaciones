import { Pressable, Text, View } from "react-native";
import { DateTimePickerAndroid } from "@react-native-community/datetimepicker";
import { C, inputBox, t } from "../theme";
import { inputDate, isoDate, parseIso } from "../lib/format";

/** Android/iOS: opens the native date picker dialog. Metro picks DateField.web.tsx for web
 *  builds instead of this file, so the native-only DateTimePickerAndroid import never reaches
 *  the web bundle. */
export function DateField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const open = () =>
    DateTimePickerAndroid.open({
      value: value ? parseIso(value) : new Date(),
      mode: "date",
      onChange: (e, d) => {
        if (e.type === "set" && d) onChange(isoDate(d));
      },
    });
  return (
    <Pressable onPress={open} style={[inputBox, { flexDirection: "row", alignItems: "center", paddingHorizontal: 12 }]}>
      <Text style={t(13.5, 600, value ? C.ink : C.placeholder, { flex: 1 })}>{value ? inputDate(value) : "dd/mm/aaaa"}</Text>
      <View style={{ width: 16, height: 16, borderRadius: 3, borderWidth: 1.5, borderColor: C.muted, borderTopWidth: 4 }} />
    </Pressable>
  );
}
