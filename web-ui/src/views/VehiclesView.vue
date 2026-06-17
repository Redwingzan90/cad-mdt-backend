<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from "vue";
import api from "@/api/client";
import { getSocket } from "@/api/socket";

const vehicles = ref<any[]>([]);
const loading = ref(false);
const search = ref("");
const plateLookup = ref("");
const plateResult = ref<any>(null);
const pagination = ref({ page: 1, total: 0, totalPages: 0 });

// Vehicle detail modal
const showDetail = ref(false);
const selectedVehicle = ref<any>(null);
const detailFlags = ref<string[]>([]);
const detailLoading = ref(false);

async function fetchVehicles(page = 1) {
  loading.value = true;
  try {
    const { data } = await api.get("/vehicles", {
      params: { page, limit: 25, search: search.value || undefined },
    });
    vehicles.value = data.data;
    pagination.value = data.pagination;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function openDetail(id: string) {
  detailLoading.value = true;
  showDetail.value = true;
  selectedVehicle.value = null;
  try {
    const { data } = await api.get(`/vehicles/${id}`);
    selectedVehicle.value = data.vehicle;
    detailFlags.value = data.flags || [];
  } catch { /* silent */ }
  finally { detailLoading.value = false; }
}

async function toggleStolen(vehicle: any) {
  try {
    const newStolen = !vehicle.stolen;
    await api.patch(`/vehicles/${vehicle.id}`, { stolen: newStolen });
    vehicle.stolen = newStolen;
    if (selectedVehicle.value?.id === vehicle.id) {
      selectedVehicle.value.stolen = newStolen;
    }
  } catch { /* silent */ }
}

async function runPlate() {
  if (!plateLookup.value.trim()) return;
  try {
    const { data } = await api.get(`/vehicles/plate/${plateLookup.value.trim().toUpperCase()}`);
    plateResult.value = data;
  } catch { plateResult.value = null; }
}

let searchTimer: any;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => fetchVehicles(), 300);
});

const socket = getSocket();

onMounted(() => {
  fetchVehicles();
  socket.on("vehicle:new", fetchVehicles);
  window.addEventListener("cad:plateResult", ((e: CustomEvent) => {
    plateResult.value = e.detail;
    if (e.detail?.plate) {
      plateLookup.value = e.detail.plate;
    }
  }) as EventListener);
});

onUnmounted(() => {
  socket.off("vehicle:new", fetchVehicles);
});
</script>

<template>
  <div class="p-6 space-y-6 max-w-[1400px] mx-auto">
    <!-- Header -->
    <div class="flex items-start justify-between">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <div class="w-1 h-8 rounded-full gradient-accent"></div>
          <h2 class="text-2xl font-bold text-white tracking-tight">Vehicle Database</h2>
        </div>
        <p class="text-sm text-dark-400 ml-[1.1rem]">Search vehicles, run plate checks, and manage registrations</p>
      </div>
    </div>

    <!-- Plate Lookup -->
    <div class="glass-card p-5">
      <div class="flex items-center gap-3 mb-4">
        <div class="w-8 h-8 rounded-lg bg-gradient-to-br from-green-500 to-emerald-500 flex items-center justify-center">
          <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
        </div>
        <h3 class="text-sm font-semibold text-white">Plate Lookup</h3>
      </div>
      <div class="flex gap-3">
        <input v-model="plateLookup" class="premium-input max-w-xs uppercase font-mono tracking-wider" placeholder="Enter plate number..." @keyup.enter="runPlate" />
        <button @click="runPlate" class="premium-btn-primary">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
          Run Plate
        </button>
      </div>

      <!-- Plate Result -->
      <div v-if="plateResult" class="mt-4 rounded-xl overflow-hidden" :class="plateResult.found ? (plateResult.flags?.length ? 'border border-red-500/30 bg-red-500/5' : 'border border-white/[0.06] bg-dark-700/30') : 'border border-white/[0.06] bg-dark-700/30'">
        <div v-if="!plateResult.found" class="px-5 py-6 text-center">
          <div class="text-4xl mb-3 opacity-40">🔍</div>
          <p class="text-dark-400 font-medium">{{ plateResult.message }}</p>
          <p class="text-dark-500 text-xs mt-1">No vehicle registered with plate {{ plateLookup.toUpperCase() }}</p>
        </div>
        <div v-else class="p-5">
          <div class="flex items-center gap-4 mb-4">
            <div class="w-14 h-14 rounded-2xl bg-dark-600/50 flex items-center justify-center text-2xl border border-white/[0.06]">🚗</div>
            <div>
              <div class="flex items-center gap-3">
                <span class="text-xl font-bold font-mono text-white tracking-wider">{{ plateResult.vehicle.plate }}</span>
                <span v-if="plateResult.vehicle.stolen" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">STOLEN</span>
              </div>
              <p class="text-sm text-dark-300">{{ plateResult.vehicle.color }} {{ plateResult.vehicle.model }} {{ plateResult.vehicle.year ? `(${plateResult.vehicle.year})` : '' }}</p>
            </div>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
            <div class="bg-dark-800/50 rounded-lg px-3 py-2">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Registration</p>
              <p class="text-sm font-semibold" :class="plateResult.vehicle.registrationStatus === 'VALID' ? 'text-green-400' : 'text-red-400'">{{ plateResult.vehicle.registrationStatus }}</p>
            </div>
            <div class="bg-dark-800/50 rounded-lg px-3 py-2">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Insurance</p>
              <p class="text-sm font-semibold" :class="plateResult.vehicle.insuranceStatus === 'VALID' ? 'text-green-400' : 'text-red-400'">{{ plateResult.vehicle.insuranceStatus }}</p>
            </div>
            <div class="bg-dark-800/50 rounded-lg px-3 py-2">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Stolen</p>
              <p class="text-sm font-semibold" :class="plateResult.vehicle.stolen ? 'text-red-400' : 'text-green-400'">{{ plateResult.vehicle.stolen ? 'YES' : 'No' }}</p>
            </div>
            <div v-if="plateResult.owner" class="bg-dark-800/50 rounded-lg px-3 py-2">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Owner</p>
              <p class="text-sm font-semibold text-dark-200">{{ plateResult.owner.name }}</p>
            </div>
          </div>

          <div v-if="plateResult.flags?.length" class="flex gap-2 flex-wrap">
            <span v-for="f in plateResult.flags" :key="f" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">{{ f }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Search & Table -->
    <div class="glass-card p-4">
      <div class="flex gap-3 items-center">
        <div class="relative flex-1 max-w-md">
          <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-dark-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
          <input v-model="search" class="premium-input pl-10" placeholder="Search by plate, model, owner..." />
        </div>
        <span class="text-xs text-dark-500">{{ pagination.total || 0 }} vehicles</span>
      </div>
    </div>

    <div class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Plate</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Vehicle</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Color</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Owner</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Registration</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Flags</th>
            <th class="px-5 py-4"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td colspan="7" class="px-5 py-1">
              <div v-for="i in 5" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div>
            </td>
          </tr>
          <tr v-else-if="!vehicles.length">
            <td colspan="7" class="px-5 py-16 text-center">
              <div class="text-5xl mb-4 opacity-40">🚗</div>
              <p class="text-dark-400 font-medium">No vehicles found</p>
              <p class="text-dark-500 text-xs mt-1">Try a different search</p>
            </td>
          </tr>
          <tr v-for="v in vehicles" :key="v.id" class="premium-table-row cursor-pointer group" @click="openDetail(v.id)">
            <td class="px-5 py-4">
              <span class="font-mono font-semibold text-dark-100 bg-white/[0.04] px-2.5 py-1 rounded-lg text-xs">{{ v.plate }}</span>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-200 font-medium group-hover:text-white transition-colors">{{ v.model }}</span>
            </td>
            <td class="px-5 py-4 text-dark-300 text-xs">{{ v.color }}</td>
            <td class="px-5 py-4">
              <div class="flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-primary-500/20 flex items-center justify-center text-[9px] font-bold text-primary-300">
                  {{ v.owner?.firstName?.[0] }}{{ v.owner?.lastName?.[0] }}
                </div>
                <span class="text-dark-300 text-xs">{{ v.owner?.firstName }} {{ v.owner?.lastName }}</span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="premium-badge" :class="v.registrationStatus === 'VALID' ? 'bg-green-500/15 text-green-300 ring-1 ring-green-500/20' : 'bg-red-500/15 text-red-300 ring-1 ring-red-500/20'">
                {{ v.registrationStatus }}
              </span>
            </td>
            <td class="px-5 py-4">
              <div class="flex gap-1.5">
                <span v-if="v.stolen" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">STOLEN</span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="text-primary-400 text-xs font-medium opacity-0 group-hover:opacity-100 transition-opacity">Details →</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="pagination.totalPages > 1" class="flex items-center justify-center gap-3">
      <button @click="fetchVehicles(pagination.page - 1)" :disabled="pagination.page <= 1" class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">← Previous</button>
      <span class="text-sm text-dark-400">Page {{ pagination.page }} of {{ pagination.totalPages }}</span>
      <button @click="fetchVehicles(pagination.page + 1)" :disabled="pagination.page >= pagination.totalPages" class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">Next →</button>
    </div>

    <!-- ==================== VEHICLE DETAIL MODAL ==================== -->
    <div v-if="showDetail" class="premium-modal-overlay" @click.self="showDetail = false">
      <div class="premium-modal-content max-w-2xl">
        <!-- Loading -->
        <div v-if="detailLoading" class="space-y-4 py-8">
          <div v-for="i in 4" :key="i" class="h-16 rounded-xl shimmer-loading"></div>
        </div>

        <template v-else-if="selectedVehicle">
          <!-- Header -->
          <div class="flex items-start justify-between mb-6">
            <div class="flex items-center gap-4">
              <div class="w-16 h-16 rounded-2xl bg-dark-600/50 flex items-center justify-center text-3xl border border-white/[0.06]">🚗</div>
              <div>
                <div class="flex items-center gap-3">
                  <h3 class="text-2xl font-bold font-mono text-white tracking-wider">{{ selectedVehicle.plate }}</h3>
                  <span v-if="selectedVehicle.stolen" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">🚨 STOLEN</span>
                </div>
                <p class="text-sm text-dark-300 mt-1">{{ selectedVehicle.color }} {{ selectedVehicle.model }} {{ selectedVehicle.year ? `(${selectedVehicle.year})` : '' }}</p>
              </div>
            </div>
            <button @click="showDetail = false" class="premium-btn-secondary text-xs px-3 py-1.5">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>

          <!-- Flags -->
          <div v-if="detailFlags.length" class="mb-6">
            <div class="flex gap-2 flex-wrap">
              <span v-for="f in detailFlags" :key="f" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">⚠️ {{ f }}</span>
            </div>
          </div>

          <!-- Vehicle Info -->
          <div class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Vehicle Information</h4>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Plate</p>
                <p class="text-sm font-mono font-semibold text-dark-100">{{ selectedVehicle.plate }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Model</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedVehicle.model }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Color</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedVehicle.color }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Year</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedVehicle.year || '—' }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Registration</p>
                <p class="text-sm font-semibold" :class="selectedVehicle.registrationStatus === 'VALID' ? 'text-green-400' : 'text-red-400'">{{ selectedVehicle.registrationStatus }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Insurance</p>
                <p class="text-sm font-semibold" :class="selectedVehicle.insuranceStatus === 'VALID' ? 'text-green-400' : 'text-red-400'">{{ selectedVehicle.insuranceStatus }}</p>
              </div>
              <div v-if="selectedVehicle.vin">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">VIN</p>
                <p class="text-sm font-mono text-dark-200">{{ selectedVehicle.vin }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Stolen Status</p>
                <button @click.stop="toggleStolen(selectedVehicle)" class="text-sm font-semibold transition-colors" :class="selectedVehicle.stolen ? 'text-red-400 hover:text-red-300' : 'text-green-400 hover:text-green-300'">
                  {{ selectedVehicle.stolen ? 'YES — Click to clear' : 'No — Click to flag stolen' }}
                </button>
              </div>
            </div>
          </div>

          <!-- Owner Info -->
          <div v-if="selectedVehicle.owner" class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Registered Owner</h4>
            <div class="flex items-center gap-4 mb-4">
              <div class="w-12 h-12 rounded-xl bg-gradient-to-br from-primary-500/30 to-purple-500/30 flex items-center justify-center text-lg font-bold text-white border border-white/[0.08]">
                {{ selectedVehicle.owner.firstName?.[0] }}{{ selectedVehicle.owner.lastName?.[0] }}
              </div>
              <div>
                <p class="text-sm font-semibold text-dark-100">{{ selectedVehicle.owner.firstName }} {{ selectedVehicle.owner.lastName }}</p>
                <p class="text-xs text-dark-400">DOB: {{ new Date(selectedVehicle.owner.dateOfBirth).toLocaleDateString() }}</p>
              </div>
            </div>

            <!-- Owner's licenses -->
            <div v-if="selectedVehicle.owner.licenses?.length" class="mb-3">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-2">Licenses</p>
              <div class="flex gap-2 flex-wrap">
                <span v-for="l in selectedVehicle.owner.licenses" :key="l.id" class="premium-badge"
                  :class="l.status === 'VALID' ? 'bg-green-500/15 text-green-300 ring-1 ring-green-500/20' : 'bg-red-500/15 text-red-300 ring-1 ring-red-500/20'">
                  {{ l.type }} — {{ l.status }}
                </span>
              </div>
            </div>

            <!-- Owner's warrants -->
            <div v-if="selectedVehicle.owner.warrants?.length" class="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3">
              <p class="text-xs font-semibold text-red-400 uppercase tracking-wider mb-2">⚠️ Active Warrants</p>
              <div v-for="w in selectedVehicle.owner.warrants" :key="w.id" class="text-sm text-red-300">
                {{ w.type }} — {{ w.charges }}
              </div>
            </div>
          </div>

          <!-- Close -->
          <div class="flex justify-end pt-2">
            <button @click="showDetail = false" class="premium-btn-secondary px-6">Close</button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
