import { clearLocalStorage, showToast, Toast } from "@raycast/api";

export async function logout() {
  try {
    // Clear any cached data or tokens
    await clearLocalStorage();
    
    // Show success message
    await showToast({
      style: Toast.Style.Success,
      title: "Logged out successfully",
      message: "Your LibreView credentials have been cleared"
    });
  } catch (error) {
    console.error('Error during logout:', error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Logout failed",
      message: error instanceof Error ? error.message : "Unknown error"
    });
  }
}

export async function isLoggedOut(): Promise<boolean> {
  try {
    return await LocalStorage.getItem(LOGGED_OUT_KEY) === "true";
  } catch {
    return false;
  }
}

export async function clearLoggedOutState() {
  await LocalStorage.removeItem(LOGGED_OUT_KEY);
}
