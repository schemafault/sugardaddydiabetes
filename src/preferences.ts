import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  username: string;
  password: string;
  unit: "mgdl" | "mmol";
}

export function getLibreViewCredentials(): Preferences {
  const preferences = getPreferenceValues<Preferences>();
  return preferences;
}
