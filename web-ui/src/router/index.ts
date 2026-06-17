import { createRouter, createWebHashHistory, type RouteRecordRaw } from "vue-router";
import { useAuthStore } from "@/stores/auth";

const routes: RouteRecordRaw[] = [
  {
    path: "/login",
    name: "Login",
    component: () => import("@/views/LoginView.vue"),
    meta: { requiresAuth: false },
  },
  {
    path: "/",
    redirect: "/dashboard",
  },
  {
    path: "/dashboard",
    name: "Dashboard",
    component: () => import("@/views/DashboardView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/dispatch",
    name: "Dispatch",
    component: () => import("@/views/DispatchView.vue"),
    meta: { requiresAuth: true, permission: "dispatch" },
  },
  {
    path: "/civilians",
    name: "Civilians",
    component: () => import("@/views/CiviliansView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/vehicles",
    name: "Vehicles",
    component: () => import("@/views/VehiclesView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/criminal",
    name: "Criminal Records",
    component: () => import("@/views/CriminalView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/reports",
    name: "Reports",
    component: () => import("@/views/ReportsView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/bolos",
    name: "BOLOs",
    component: () => import("@/views/BolosView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/evidence",
    name: "Evidence",
    component: () => import("@/views/EvidenceView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/officers",
    name: "Officers",
    component: () => import("@/views/OfficersView.vue"),
    meta: { requiresAuth: true },
  },
  {
    path: "/admin",
    name: "Admin",
    component: () => import("@/views/AdminView.vue"),
    meta: { requiresAuth: true, permission: "admin", altPermissions: ["supervisor", "manage_officers"] },
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes,
});

// Navigation guard
router.beforeEach((to, _from, next) => {
  const authStore = useAuthStore();

  if (to.meta.requiresAuth !== false && !authStore.isAuthenticated) {
    return next("/login");
  }

  if (to.meta.permission) {
    const hasMain = authStore.hasPermission(to.meta.permission as string);
    const altPerms = (to.meta as any).altPermissions as string[] | undefined;
    const hasAlt = altPerms ? authStore.hasAnyPermission(...altPerms) : false;
    if (!hasMain && !hasAlt) {
      return next("/dashboard");
    }
  }

  next();
});

export default router;
