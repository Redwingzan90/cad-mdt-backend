<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import api from "@/api/client";
import { getSocket } from "@/api/socket";
import { useAuthStore } from "@/stores/auth";
import { useRouter } from "vue-router";

const authStore = useAuthStore();
const router = useRouter();

const dashboard = ref<any>(null);
const loading = ref(true);
const currentTime = ref(new Date());

// Update clock
setInterval(() => {
  currentTime.value = new Date();
  const el = document.getElementById("clock");
  if (el) {
    el.textContent = currentTime.value.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }
}, 1000);

const priorityLabels: Record<string, { label: string; class: string }> = {
  PRIORITY_1: { label: "P1", class: "bg-red-500/20 text-red-400 border-red-500/30" },
  PRIORITY_2: { label: "P2", class: "bg-orange-500/20 text-orange-400 border-orange-500/30" },
  PRIORITY_3: { label: "P3", class: "bg-yellow-500/20 text-yellow-400 border-yellow-500/30" },
  PRIORITY_4: { label: "P4", class: "bg-blue-500/20 text-blue-400 border-blue-500/30" },
};

const statusColors: Record<string, string> = {
  AVAILABLE: "status-available",
  BUSY: "status-busy",
  EN_ROUTE: "status-en-route",
  ON_SCENE: "status-on-scene",
  TRANSPORTING: "status-transporting",
  OUT_OF_SERVICE: "status-out-of-service",
  BREAK: "status-break",
  OFF_DUTY: "status-off-duty",
};

async function fetchDashboard() {
  loading.value = true;
  try {
    const { data } = await api.get("/dashboard");
    dashboard.value = data;
  } catch {
    // Silent fail
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  fetchDashboard();

  // Listen for real-time updates
  const socket = getSocket();
  socket.on("dispatch:call:new", fetchDashboard);
  socket.on("dispatch:call:update", fetchDashboard);
  socket.on("unit:status:update", fetchDashboard);
});
</script>

<template>
  <div class="p-4 space-y-4">
    <!-- Stats Cards -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
      <div class="card p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs text-dark-400 uppercase tracking-wider">Officers On Duty</p>
            <p class="text-2xl font-bold text-white mt-1">
              {{ dashboard?.stats?.officersOnDuty ?? "—" }}
            </p>
          </div>
          <div class="text-3xl opacity-60">👮</div>
        </div>
      </div>

      <div class="card p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs text-dark-400 uppercase tracking-wider">Active Calls</p>
            <p class="text-2xl font-bold text-white mt-1">
              {{ dashboard?.stats?.activeCallsCount ?? "—" }}
            </p>
          </div>
          <div class="text-3xl opacity-60">🚨</div>
        </div>
      </div>

      <div class="card p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs text-dark-400 uppercase tracking-wider">Arrests Today</p>
            <p class="text-2xl font-bold text-white mt-1">
              {{ dashboard?.stats?.arrestsToday ?? "—" }}
            </p>
          </div>
          <div class="text-3xl opacity-60">🔒</div>
        </div>
      </div>

      <div class="card p-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs text-dark-400 uppercase tracking-wider">Calls Today</p>
            <p class="text-2xl font-bold text-white mt-1">
              {{ dashboard?.stats?.callsToday ?? "—" }}
            </p>
          </div>
          <div class="text-3xl opacity-60">📞</div>
        </div>
      </div>
    </div>

    <!-- Main Grid -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <!-- Active Calls -->
      <div class="lg:col-span-2 card">
        <div class="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 class="text-sm font-semibold text-dark-200 flex items-center gap-2">
            🚨 Active Dispatch Calls
          </h2>
          <button @click="router.push('/dispatch')" class="text-xs text-primary-400 hover:text-primary-300">
            View All →
          </button>
        </div>
        <div class="max-h-80 overflow-y-auto">
          <div v-if="loading" class="p-8 text-center text-dark-500">Loading...</div>
          <div v-else-if="!dashboard?.activeCalls?.length" class="p-8 text-center text-dark-500">
            No active calls
          </div>
          <div
            v-for="call in dashboard?.activeCalls?.slice(0, 8)"
            :key="call.id"
            class="flex items-center gap-3 px-4 py-3 border-b border-dark-700/50 hover:bg-dark-700/30 transition-colors"
          >
            <span
              class="text-xs font-bold px-2 py-1 rounded border min-w-[32px] text-center"
              :class="priorityLabels[call.priority]?.class"
            >
              {{ priorityLabels[call.priority]?.label }}
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm text-dark-100 truncate">{{ call.type }} — {{ call.location }}</p>
              <p class="text-xs text-dark-500 truncate">
                {{ call.callNumber }} • {{ call.assignments?.length || 0 }} unit(s)
              </p>
            </div>
            <span class="text-xs text-dark-500 whitespace-nowrap">
              {{ new Date(call.createdAt).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Officers On Duty -->
      <div class="card">
        <div class="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 class="text-sm font-semibold text-dark-200 flex items-center gap-2">
            👮 On Duty
          </h2>
          <button @click="router.push('/officers')" class="text-xs text-primary-400 hover:text-primary-300">
            View All →
          </button>
        </div>
        <div class="max-h-80 overflow-y-auto">
          <div v-if="!dashboard?.activeOfficers?.length" class="p-8 text-center text-dark-500">
            No officers on duty
          </div>
          <div
            v-for="officer in dashboard?.activeOfficers?.slice(0, 15)"
            :key="officer.id"
            class="flex items-center gap-3 px-4 py-2.5 border-b border-dark-700/50 hover:bg-dark-700/30 transition-colors"
          >
            <span class="status-dot flex-shrink-0" :class="statusColors[officer.status]" />
            <div class="flex-1 min-w-0">
              <p class="text-sm text-dark-100 truncate">
                {{ officer.callsign || officer.badgeNumber }}
              </p>
              <p class="text-xs text-dark-500 truncate">
                {{ officer.firstName }} {{ officer.lastName }}
              </p>
            </div>
            <span class="text-xs text-dark-500">{{ officer.status.replace(/_/g, " ") }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Bottom Row -->
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <!-- BOLOs -->
      <div class="card">
        <div class="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 class="text-sm font-semibold text-dark-200 flex items-center gap-2">
            ⚠️ Active BOLOs
          </h2>
        </div>
        <div class="max-h-60 overflow-y-auto">
          <div v-if="!dashboard?.activeBolos?.length" class="p-6 text-center text-dark-500 text-sm">
            No active BOLOs
          </div>
          <div
            v-for="bolo in dashboard?.activeBolos?.slice(0, 5)"
            :key="bolo.id"
            class="px-4 py-3 border-b border-dark-700/50"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="badge-danger text-[10px]">{{ bolo.type }}</span>
              <span class="text-xs text-dark-500">{{ bolo.priority }}</span>
            </div>
            <p class="text-xs text-dark-300 line-clamp-2">{{ bolo.description }}</p>
          </div>
        </div>
      </div>

      <!-- Warrants -->
      <div class="card">
        <div class="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 class="text-sm font-semibold text-dark-200 flex items-center gap-2">
            📋 Active Warrants
          </h2>
        </div>
        <div class="max-h-60 overflow-y-auto">
          <div v-if="!dashboard?.activeWarrants?.length" class="p-6 text-center text-dark-500 text-sm">
            No active warrants
          </div>
          <div
            v-for="warrant in dashboard?.activeWarrants?.slice(0, 5)"
            :key="warrant.id"
            class="px-4 py-2.5 border-b border-dark-700/50"
          >
            <p class="text-sm text-dark-200">
              {{ warrant.civilian?.firstName }} {{ warrant.civilian?.lastName }}
            </p>
            <p class="text-xs text-dark-500">{{ warrant.type }} — {{ warrant.charges }}</p>
          </div>
        </div>
      </div>

      <!-- Announcements -->
      <div class="card">
        <div class="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 class="text-sm font-semibold text-dark-200 flex items-center gap-2">
            📢 Announcements
          </h2>
        </div>
        <div class="max-h-60 overflow-y-auto">
          <div v-if="!dashboard?.announcements?.length" class="p-6 text-center text-dark-500 text-sm">
            No announcements
          </div>
          <div
            v-for="ann in dashboard?.announcements?.slice(0, 5)"
            :key="ann.id"
            class="px-4 py-3 border-b border-dark-700/50"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-semibold text-dark-200">{{ ann.title }}</span>
            </div>
            <p class="text-xs text-dark-400 line-clamp-2">{{ ann.content }}</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
