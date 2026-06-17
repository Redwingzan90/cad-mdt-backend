<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import api from "@/api/client";

const officers = ref<any[]>([]);
const loading = ref(false);
const filter = ref("all"); // all, on-duty, off-duty

const filteredOfficers = computed(() => {
  if (filter.value === "on-duty") return officers.value.filter(o => o.status !== "OFF_DUTY");
  if (filter.value === "off-duty") return officers.value.filter(o => o.status === "OFF_DUTY");
  return officers.value;
});

const statusColors: Record<string, string> = {
  AVAILABLE: "status-available", BUSY: "status-busy", EN_ROUTE: "status-en-route",
  ON_SCENE: "status-on-scene", TRANSPORTING: "status-transporting",
  OUT_OF_SERVICE: "status-out-of-service", BREAK: "status-break", OFF_DUTY: "status-off-duty",
};

async function fetchOfficers() {
  loading.value = true;
  try {
    const { data } = await api.get("/officers?limit=100");
    officers.value = data.data;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

onMounted(() => fetchOfficers());
</script>

<template>
  <div class="p-4 space-y-4">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold text-white">Officers</h2>
      <div class="flex gap-1 bg-dark-800 rounded-lg p-1">
        <button v-for="f in [{ key: 'all', label: 'All' }, { key: 'on-duty', label: 'On Duty' }, { key: 'off-duty', label: 'Off Duty' }]"
          :key="f.key" @click="filter = f.key"
          class="px-3 py-1.5 rounded-md text-xs font-medium transition-colors"
          :class="filter === f.key ? 'bg-primary-600 text-white' : 'text-dark-400 hover:text-dark-200'">
          {{ f.label }}
        </button>
      </div>
    </div>

    <div v-if="loading" class="text-center py-12 text-dark-500">Loading...</div>
    <div v-else-if="!filteredOfficers.length" class="text-center py-12 text-dark-500">No officers found</div>
    <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
      <div v-for="o in filteredOfficers" :key="o.id" class="card p-4 hover:bg-dark-700/50 transition-colors">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-primary-600/20 flex items-center justify-center text-primary-400 font-bold text-sm flex-shrink-0">
            {{ o.firstName[0] }}{{ o.lastName[0] }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="text-sm font-semibold text-dark-100">{{ o.firstName }} {{ o.lastName }}</span>
              <span class="status-dot" :class="statusColors[o.status]" />
            </div>
            <p class="text-xs text-dark-400">{{ o.callsign || o.badgeNumber }} • {{ o.rank?.name }}</p>
            <p class="text-xs text-dark-500">{{ o.department?.name }}</p>
          </div>
        </div>
        <div class="mt-2 flex items-center justify-between">
          <span class="text-xs text-dark-500 capitalize">{{ o.status.replace(/_/g, " ").toLowerCase() }}</span>
          <span v-if="o.unit?.vehicle" class="text-xs text-dark-500">{{ o.unit.vehicle }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
