import { createElement } from "react";
import { C } from "../theme";

/** Web: a real HTML date input (native browser calendar, no extra dependency) — value/onChange
 *  already speak the same "YYYY-MM-DD" ISO format the rest of the app uses, so no conversion is
 *  needed here unlike the Android version (which talks to a Date object). Metro picks this file
 *  over DateField.tsx when bundling for web. */
export function DateField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return createElement("input", {
    type: "date",
    value,
    onChange: (e: { target: { value: string } }) => onChange(e.target.value),
    style: {
      backgroundColor: C.card,
      border: `1px solid ${C.border}`,
      borderRadius: 12,
      height: 48,
      padding: "0 14px",
      fontFamily: "Manrope_600SemiBold, sans-serif",
      fontSize: 13.5,
      color: value ? C.ink : C.placeholder,
      width: "100%",
      boxSizing: "border-box",
      outline: "none",
    },
  });
}
