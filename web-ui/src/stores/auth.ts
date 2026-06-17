import { defineStore } from "pinia";
import { ref, computed } from "vue";
import api from "@/api/client";
import { disconnectSocket } from "@/api/socket";

export interface OfficerInfo {
  id: string;
  firstName: string;
  lastName: string;
  badgeNumber: string;
  department: { id: string; name: string; code: string; color?: string };
  rank: { id: string; name: string; level: number };
  callsign: string | null;
  status: string;
}

export interface UserInfo {
  id: string;
  username: string;
  permissions: string[];
  officer: OfficerInfo | null;
}

export const useAuthStore = defineStore("auth", () => {
  const token = ref<string | null>(localStorage.getItem("cad_token"));
  const user = ref<UserInfo | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);

  const isAuthenticated = computed(() => !!token.value && !!user.value);

  function hasPermission(permission: string): boolean {
    if (!user.value) return false;
    if (user.value.permissions.includes("admin")) return true;
    return user.value.permissions.includes(permission);
  }

  function hasAnyPermission(...permissions: string[]): boolean {
    if (!user.value) return false;
    if (user.value.permissions.includes("admin")) return true;
    return permissions.some((p) => user.value!.permissions.includes(p));
  }

  async function login(username: string, password: string) {
    loading.value = true;
    error.value = null;

    try {
      const { data } = await api.post("/auth/login", { username, password });
      token.value = data.token;
      user.value = data.user;
      localStorage.setItem("cad_token", data.token);
    } catch (err: any) {
      error.value = err.response?.data?.error || "Login failed.";
      throw err;
    } finally {
      loading.value = false;
    }
  }

  async function logout() {
    try {
      await api.post("/auth/logout");
    } catch {
      // Ignore logout errors
    }

    token.value = null;
    user.value = null;
    localStorage.removeItem("cad_token");
    disconnectSocket();
  }

  async function fetchUser() {
    if (!token.value) return;

    try {
      const { data } = await api.get("/auth/me");
      user.value = data;
    } catch {
      token.value = null;
      user.value = null;
      localStorage.removeItem("cad_token");
    }
  }

  // Fetch user on store init if token exists
  if (token.value && !user.value) {
    fetchUser();
  }

  return {
    token,
    user,
    loading,
    error,
    isAuthenticated,
    hasPermission,
    hasAnyPermission,
    login,
    logout,
    fetchUser,
  };
});
