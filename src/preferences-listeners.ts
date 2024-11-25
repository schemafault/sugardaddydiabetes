import { updatePreference } from "@raycast/api";

export async function clearThresholds() {
  await updatePreference("lowThreshold", "");
  await updatePreference("highThreshold", "");
} 