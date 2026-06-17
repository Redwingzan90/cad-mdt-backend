<script setup lang="ts">
import { ref, onMounted } from "vue";
import api from "@/api/client";

const tab = ref<"arrests" | "citations" | "warnings" | "warrants">("arrests");
const records = ref<any[]>([]);
const loading = ref(false);
const pagination = ref({ page: 1, total: 0, totalPages: 0 });

const tabs = [
  { key: "arrests", label: "Arrests", icon: "🔒" },
  { key: "citations", label: "Citations", icon: "📝" },
  { key: "warnings", label: "Warnings", icon: "⚠️" },
  { key: "warrants", label: "Warrants", icon: "📋" },
];

async function fetchRecords(page = 1) {
  loading.value = true;
  try {
    const { data } = await api.get(`/criminal/${tab.value}`, { params: { page, limit: 25 } });
    records.value = data.data;
    pagination.value = data.pagination;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

function switchTab(t: string) {
  tab.value = t as any;
  fetchRecords();
}

onMounted(() => fetchRecords());
</script>

<template>
  <div class="p-4 space-y-4">
    <h2 class="text-lg font-bold text-white">Criminal Records</h2>

    <!-- Tabs -->
    <div class="flex gap-1 bg-dark-800 rounded-lg p-1 w-fit">
      <button
        v-for="t in tabs"
        :key="t.key"
        @click="switchTab(t.key)"
        class="px-4 py-2 rounded-md text-sm font-medium transition-colors"
        :class="tab === t.key ? 'bg-primary-600 text-white' : 'text-dark-400 hover:text-dark-200'"
      >
        {{ t.icon }} {{ t.label }}
      </button>
    </div>

    <!-- Table -->
    <div class="card overflow-hidden">
      <table class="w-full text-sm">
        <thead class="bg-dark-900/50">
          <tr class="text-left text-dark-400 text-xs uppercase tracking-wider">
            <th v-if="tab === 'arrests'" class="px-4 py-3">Report #</th>
            <th v-if="tab === 'citations'" class="px-4 py-3">Citation #</th>
            <th class="px-4 py-3">Civilian</th>
            <th class="px-4 py-3">Officer</th>
            <th class="px-4 py-3">Location</th>
            <th v-if="tab === 'arrests'" class="px-4 py-3">Charges</th>
            <th v-if="tab === 'citations'" class="px-4 py-3">Violation</th>
            <th v-if="tab === 'warnings'" class="px-4 py-3">Type</th>
            <th v-if="tab === 'warrants'" class="px-4 py-3">Type</th>
            <th class="px-4 py-3">Date</th>
            <th v-if="tab === 'warrants'" class="px-4 py-3">Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="8" class="px-4 py-8 text-center text-dark-500">Loading...</td></tr>
          <tr v-else-if="!records.length"><td colspan="8" class="px-4 py-8 text-center text-dark-500">No records found</td></tr>
          <tr v-for="r in records" :key="r.id" class="table-row">
            <td class="px-4 py-3 font-mono text-dark-200">{{ r.reportNumber || r.citationNumber || r.warrantNumber || "—" }}</td>
            <td class="px-4 py-3 text-dark-200">{{ r.civilian?.firstName }} {{ r.civilian?.lastName }}</td>
            <td class="px-4 py-3 text-dark-400">{{ r.officer?.firstName }} {{ r.officer?.lastName }}</td>
            <td class="px-4 py-3 text-dark-400 truncate max-w-[150px]">{{ r.location || r.issuedBy || "—" }}</td>
            <td v-if="tab === 'arrests'" class="px-4 py-3 text-dark-300 text-xs max-w-[200px] truncate">{{ r.charges }}</td>
            <td v-if="tab === 'citations'" class="px-4 py-3 text-dark-300">{{ r.violation }}</td>
            <td v-if="tab === 'warnings'" class="px-4 py-3 text-dark-300">{{ r.type }}</td>
            <td v-if="tab === 'warrants'" class="px-4 py-3 text-dark-300">{{ r.type }}</td>
            <td class="px-4 py-3 text-dark-500 text-xs">{{ new Date(r.dateTime || r.issuedAt).toLocaleDateString() }}</td>
            <td v-if="tab === 'warrants'" class="px-4 py-3"><span :class="r.status === 'ACTIVE' ? 'badge-danger' : 'badge-success'">{{ r.status }}</span></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
