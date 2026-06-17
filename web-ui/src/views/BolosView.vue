<script setup lang="ts">
import { ref, onMounted } from "vue";
import api from "@/api/client";

const bolos = ref<any[]>([]);
const loading = ref(false);
const showCreateModal = ref(false);
const newBolo = ref({
  type: "PERSON", priority: "MEDIUM", description: "", lastKnownLocation: "", expiresAt: "",
});

async function fetchBolos() {
  loading.value = true;
  try {
    const { data } = await api.get("/bolos/active");
    bolos.value = data;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function createBolo() {
  try {
    await api.post("/bolos", newBolo.value);
    showCreateModal.value = false;
    newBolo.value = { type: "PERSON", priority: "MEDIUM", description: "", lastKnownLocation: "", expiresAt: "" };
    fetchBolos();
  } catch { /* silent */ }
}

async function deactivateBolo(id: string) {
  try {
    await api.delete(`/bolos/${id}`);
    bolos.value = bolos.value.filter(b => b.id !== id);
  } catch { /* silent */ }
}

const priorityColors: Record<string, string> = {
  CRITICAL: "border-l-red-500 bg-red-500/5", HIGH: "border-l-orange-500 bg-orange-500/5",
  MEDIUM: "border-l-yellow-500 bg-yellow-500/5", LOW: "border-l-blue-500 bg-blue-500/5",
};

onMounted(() => fetchBolos());
</script>

<template>
  <div class="p-4 space-y-4">
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold text-white">BOLOs</h2>
      <button @click="showCreateModal = true" class="btn-primary">+ New BOLO</button>
    </div>

    <div v-if="loading" class="text-center py-12 text-dark-500">Loading...</div>
    <div v-else-if="!bolos.length" class="text-center py-12 text-dark-500">
      <div class="text-4xl mb-3">✅</div><p>No active BOLOs</p>
    </div>
    <div v-else class="space-y-2">
      <div v-for="bolo in bolos" :key="bolo.id"
        class="card p-4 border-l-4" :class="priorityColors[bolo.priority]">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-2">
              <span class="badge-danger">{{ bolo.type }}</span>
              <span class="badge" :class="bolo.priority === 'CRITICAL' ? 'badge-danger' : bolo.priority === 'HIGH' ? 'badge-warning' : 'badge-info'">{{ bolo.priority }}</span>
              <span class="text-xs text-dark-500">{{ bolo.creator?.callsign || bolo.creator?.firstName }}</span>
            </div>
            <p class="text-sm text-dark-200 mb-1">{{ bolo.description }}</p>
            <p v-if="bolo.lastKnownLocation" class="text-xs text-dark-400">📍 {{ bolo.lastKnownLocation }}</p>
            <div v-if="bolo.targetCiv" class="text-xs text-dark-400 mt-1">Target: {{ bolo.targetCiv.firstName }} {{ bolo.targetCiv.lastName }}</div>
            <div v-if="bolo.targetVehicle" class="text-xs text-dark-400 mt-1">Vehicle: {{ bolo.targetVehicle.plate }} — {{ bolo.targetVehicle.color }} {{ bolo.targetVehicle.model }}</div>
          </div>
          <button @click="deactivateBolo(bolo.id)" class="btn-sm btn-ghost text-red-400 hover:text-red-300 ml-3">✕</button>
        </div>
      </div>
    </div>

    <!-- Create Modal -->
    <div v-if="showCreateModal" class="modal-overlay" @click.self="showCreateModal = false">
      <div class="modal-content">
        <h3 class="text-lg font-bold text-white mb-4">New BOLO</h3>
        <form @submit.prevent="createBolo" class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div><label class="text-xs text-dark-400 mb-1 block">Type</label>
              <select v-model="newBolo.type" class="select">
                <option value="PERSON">Person</option><option value="VEHICLE">Vehicle</option><option value="OFFICER_SAFETY">Officer Safety</option>
              </select>
            </div>
            <div><label class="text-xs text-dark-400 mb-1 block">Priority</label>
              <select v-model="newBolo.priority" class="select">
                <option value="LOW">Low</option><option value="MEDIUM">Medium</option><option value="HIGH">High</option><option value="CRITICAL">Critical</option>
              </select>
            </div>
          </div>
          <div><label class="text-xs text-dark-400 mb-1 block">Description</label><textarea v-model="newBolo.description" class="input" rows="3" required /></div>
          <div><label class="text-xs text-dark-400 mb-1 block">Last Known Location</label><input v-model="newBolo.lastKnownLocation" class="input" /></div>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="showCreateModal = false" class="btn-secondary">Cancel</button>
            <button type="submit" class="btn-primary">Create BOLO</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
