<script setup lang="ts">
import { ref, computed, onMounted } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";
import { toISODateTime } from "@/utils/dateUtils";

const auth = useAuthStore();
const tab = ref<"incidents" | "crashes" | "use-of-force" | "investigations">("incidents");
const reports = ref<any[]>([]);
const loading = ref(false);
const pagination = ref({ page: 1, total: 0, totalPages: 0 });
const showCreateModal = ref(false);

// Report detail modal
const showDetail = ref(false);
const selectedReport = ref<any>(null);
const detailLoading = ref(false);

const tabs = [
  { key: "incidents", label: "Incident", icon: "📋", color: "from-blue-500 to-cyan-500" },
  { key: "crashes", label: "Crash", icon: "🚗", color: "from-orange-500 to-red-500" },
  { key: "use-of-force", label: "Use of Force", icon: "💪", color: "from-red-500 to-pink-500" },
  { key: "investigations", label: "Investigation", icon: "🔍", color: "from-purple-500 to-indigo-500" },
];

const newReport = ref({
  location: "",
  dateTime: "",
  type: "",
  narrative: "",
  weather: "",
  roadConditions: "",
  injuries: false,
  fatalities: false,
  forceType: "",
  subjectName: "",
  witnessInfo: "",
  medicalAttention: false,
  title: "",
  description: "",
  priority: 3,
});

function resetForm() {
  newReport.value = {
    location: "", dateTime: "", type: "", narrative: "",
    weather: "", roadConditions: "", injuries: false, fatalities: false,
    forceType: "", subjectName: "", witnessInfo: "", medicalAttention: false,
    title: "", description: "", priority: 3,
  };
}

async function fetchReports(page = 1) {
  loading.value = true;
  try {
    const { data } = await api.get(`/reports/${tab.value}`, { params: { page, limit: 25 } });
    reports.value = data.data;
    pagination.value = data.pagination;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function openDetail(report: any) {
  detailLoading.value = true;
  showDetail.value = true;
  selectedReport.value = null;
  try {
    const { data } = await api.get(`/reports/${tab.value}/${report.id}`);
    selectedReport.value = data;
  } catch {
    // Fallback to list data if detail endpoint fails
    selectedReport.value = report;
  }
  finally { detailLoading.value = false; }
}

async function updateStatus(report: any, status: string) {
  try {
    await api.patch(`/reports/${tab.value}/${report.id}`, { status });
    report.status = status;
    if (selectedReport.value?.id === report.id) {
      selectedReport.value.status = status;
    }
  } catch (err: any) {
    console.error('Failed to update status:', err?.response?.data?.error || err.message);
  }
}

function switchTab(t: string) {
  tab.value = t as any;
  fetchReports();
}

async function createReport() {
  const officerId = auth.user?.officer?.id;
  if (!officerId) return;

  try {
    if (tab.value === "incidents") {
      await api.post("/reports/incidents", {
        officerId,
        location: newReport.value.location,
        dateTime: toISODateTime(newReport.value.dateTime),
        type: newReport.value.type,
        narrative: newReport.value.narrative,
      });
    } else if (tab.value === "crashes") {
      await api.post("/reports/crashes", {
        officerId,
        location: newReport.value.location,
        dateTime: toISODateTime(newReport.value.dateTime),
        narrative: newReport.value.narrative,
        weather: newReport.value.weather || undefined,
        roadConditions: newReport.value.roadConditions || undefined,
        injuries: newReport.value.injuries,
        fatalities: newReport.value.fatalities,
      });
    } else if (tab.value === "use-of-force") {
      await api.post("/reports/use-of-force", {
        officerId,
        location: newReport.value.location,
        dateTime: toISODateTime(newReport.value.dateTime),
        forceType: newReport.value.forceType,
        subjectName: newReport.value.subjectName,
        narrative: newReport.value.narrative,
        witnessInfo: newReport.value.witnessInfo || undefined,
        medicalAttention: newReport.value.medicalAttention,
      });
    } else if (tab.value === "investigations") {
      await api.post("/reports/investigations", {
        officerId,
        title: newReport.value.title,
        description: newReport.value.description,
        priority: newReport.value.priority,
        startDate: toISODateTime(newReport.value.dateTime),
      });
    }
    showCreateModal.value = false;
    resetForm();
    fetchReports();
  } catch { /* silent */ }
}

const statusConfig: Record<string, { class: string; glow: string }> = {
  DRAFT: { class: "bg-amber-500/15 text-amber-300 ring-1 ring-amber-500/20", glow: "shadow-amber-500/10" },
  SUBMITTED: { class: "bg-blue-500/15 text-blue-300 ring-1 ring-blue-500/20", glow: "shadow-blue-500/10" },
  APPROVED: { class: "bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/20", glow: "shadow-emerald-500/10" },
  REJECTED: { class: "bg-red-500/15 text-red-300 ring-1 ring-red-500/20", glow: "shadow-red-500/10" },
  ARCHIVED: { class: "bg-purple-500/15 text-purple-300 ring-1 ring-purple-500/20", glow: "shadow-purple-500/10" },
  OPEN: { class: "bg-blue-500/15 text-blue-300 ring-1 ring-blue-500/20", glow: "shadow-blue-500/10" },
  IN_PROGRESS: { class: "bg-amber-500/15 text-amber-300 ring-1 ring-amber-500/20", glow: "shadow-amber-500/10" },
  CLOSED: { class: "bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/20", glow: "shadow-emerald-500/10" },
  COLD_CASE: { class: "bg-purple-500/15 text-purple-300 ring-1 ring-purple-500/20", glow: "shadow-purple-500/10" },
};

const isAdmin = computed(() => auth.hasAnyPermission('admin', 'supervisor'));

const activeTabMeta = computed(() => tabs.find(t => t.key === tab.value));

async function deleteReport(id: string) {
  if (!confirm('Delete this report? This action cannot be undone.')) return;
  try {
    await api.delete(`/reports/${tab.value}/${id}`);
    fetchReports();
    showDetail.value = false;
    selectedReport.value = null;
  } catch (err: any) {
    alert(err?.response?.data?.error || 'Failed to delete report.');
  }
}

onMounted(() => fetchReports());
</script>

<template>
  <div class="p-6 space-y-6 max-w-[1400px] mx-auto">
    <!-- Header -->
    <div class="flex items-start justify-between">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <div class="w-1 h-8 rounded-full gradient-accent"></div>
          <h2 class="text-2xl font-bold text-white tracking-tight">Reports</h2>
        </div>
        <p class="text-sm text-dark-400 ml-[1.1rem]">Create and manage department reports</p>
      </div>
      <button @click="resetForm(); showCreateModal = true" class="premium-btn-primary">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
        New Report
      </button>
    </div>

    <!-- Tab Bar -->
    <div class="glass-card p-1.5 inline-flex gap-1">
      <button v-for="t in tabs" :key="t.key" @click="switchTab(t.key)"
        class="relative px-5 py-2.5 rounded-xl text-sm font-medium transition-all duration-300 flex items-center gap-2"
        :class="tab === t.key
          ? 'bg-white/[0.08] text-white shadow-lg'
          : 'text-dark-400 hover:text-dark-200 hover:bg-white/[0.03]'">
        <span class="text-base">{{ t.icon }}</span>
        <span>{{ t.label }}</span>
        <div v-if="tab === t.key"
          class="absolute bottom-0 left-1/2 -translate-x-1/2 w-8 h-0.5 rounded-full gradient-accent"></div>
      </button>
    </div>

    <!-- Table -->
    <div class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Report #</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Type</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Officer</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Location</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Date</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Status</th>
            <th class="px-5 py-4"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td colspan="7" class="px-5 py-1">
              <div v-for="i in 5" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div>
            </td>
          </tr>
          <tr v-else-if="!reports.length">
            <td colspan="7" class="px-5 py-16 text-center">
              <div class="text-5xl mb-4 opacity-40">📋</div>
              <p class="text-dark-400 font-medium">No {{ activeTabMeta?.label.toLowerCase() }} reports found</p>
              <p class="text-dark-500 text-xs mt-1">Create your first report to get started</p>
            </td>
          </tr>
          <tr v-for="r in reports" :key="r.id" class="premium-table-row cursor-pointer group" @click="openDetail(r)">
            <td class="px-5 py-4">
              <span class="font-mono text-xs text-dark-300 bg-white/[0.04] px-2.5 py-1 rounded-lg">{{ r.reportNumber }}</span>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-200 font-medium group-hover:text-white transition-colors">{{ r.type || r.forceType || r.title || "—" }}</span>
            </td>
            <td class="px-5 py-4">
              <div class="flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-primary-500/20 flex items-center justify-center text-[10px] font-bold text-primary-300">
                  {{ r.officer?.firstName?.[0] }}{{ r.officer?.lastName?.[0] }}
                </div>
                <span class="text-dark-300 text-xs">{{ r.officer?.firstName }} {{ r.officer?.lastName }}</span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-400 text-xs truncate max-w-[200px] block">{{ r.location || "—" }}</span>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-500 text-xs">{{ new Date(r.dateTime || r.startDate || r.createdAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) }}</span>
            </td>
            <td class="px-5 py-4">
              <span class="premium-badge shadow-lg" :class="[statusConfig[r.status]?.class, statusConfig[r.status]?.glow]">
                <span class="w-1.5 h-1.5 rounded-full" :class="{
                  'bg-amber-400': r.status === 'DRAFT' || r.status === 'IN_PROGRESS',
                  'bg-blue-400': r.status === 'SUBMITTED' || r.status === 'OPEN',
                  'bg-emerald-400': r.status === 'APPROVED' || r.status === 'CLOSED',
                  'bg-red-400': r.status === 'REJECTED',
                  'bg-purple-400': r.status === 'ARCHIVED' || r.status === 'COLD_CASE',
                }"></span>
                {{ r.status?.replace(/_/g, ' ') }}
              </span>
            </td>
            <td class="px-5 py-4">
              <span class="text-primary-400 text-xs font-medium opacity-0 group-hover:opacity-100 transition-opacity">View →</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Pagination -->
    <div v-if="pagination.totalPages > 1" class="flex items-center justify-center gap-3">
      <button @click="fetchReports(pagination.page - 1)" :disabled="pagination.page <= 1"
        class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">← Previous</button>
      <div class="flex items-center gap-1.5">
        <button v-for="p in Math.min(pagination.totalPages, 7)" :key="p"
          @click="fetchReports(p)"
          class="w-8 h-8 rounded-lg text-xs font-medium transition-all duration-200"
          :class="p === pagination.page
            ? 'bg-primary-500 text-white shadow-lg shadow-primary-500/30'
            : 'text-dark-400 hover:bg-white/[0.05] hover:text-dark-200'">
          {{ p }}
        </button>
      </div>
      <button @click="fetchReports(pagination.page + 1)" :disabled="pagination.page >= pagination.totalPages"
        class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">Next →</button>
    </div>

    <!-- ==================== REPORT DETAIL MODAL ==================== -->
    <div v-if="showDetail" class="premium-modal-overlay" @click.self="showDetail = false">
      <div class="premium-modal-content max-w-3xl">
        <!-- Loading -->
        <div v-if="detailLoading" class="space-y-4 py-8">
          <div v-for="i in 4" :key="i" class="h-16 rounded-xl shimmer-loading"></div>
        </div>

        <template v-else-if="selectedReport">
          <!-- Header -->
          <div class="flex items-start justify-between mb-6">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-2xl flex items-center justify-center text-xl border border-white/[0.08]"
                :class="{
                  'bg-gradient-to-br from-blue-500/30 to-cyan-500/30': tab === 'incidents',
                  'bg-gradient-to-br from-orange-500/30 to-red-500/30': tab === 'crashes',
                  'bg-gradient-to-br from-red-500/30 to-pink-500/30': tab === 'use-of-force',
                  'bg-gradient-to-br from-purple-500/30 to-indigo-500/30': tab === 'investigations',
                }">
                {{ activeTabMeta?.icon }}
              </div>
              <div>
                <div class="flex items-center gap-3">
                  <h3 class="text-xl font-bold text-white">{{ selectedReport.reportNumber }}</h3>
                  <span class="premium-badge shadow-lg" :class="[statusConfig[selectedReport.status]?.class, statusConfig[selectedReport.status]?.glow]">
                    <span class="w-1.5 h-1.5 rounded-full" :class="{
                      'bg-amber-400': selectedReport.status === 'DRAFT' || selectedReport.status === 'IN_PROGRESS',
                      'bg-blue-400': selectedReport.status === 'SUBMITTED' || selectedReport.status === 'OPEN',
                      'bg-emerald-400': selectedReport.status === 'APPROVED' || selectedReport.status === 'CLOSED',
                      'bg-red-400': selectedReport.status === 'REJECTED',
                      'bg-purple-400': selectedReport.status === 'ARCHIVED' || selectedReport.status === 'COLD_CASE',
                    }"></span>
                    {{ selectedReport.status?.replace(/_/g, ' ') }}
                  </span>
                </div>
                <p class="text-sm text-dark-400 mt-1">{{ activeTabMeta?.label }} Report</p>
              </div>
            </div>
            <button @click="showDetail = false" class="premium-btn-secondary text-xs px-3 py-1.5">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>

          <!-- Report Info -->
          <div class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Report Details</h4>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div v-if="selectedReport.type || selectedReport.forceType || selectedReport.title">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Type</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.type || selectedReport.forceType || selectedReport.title }}</p>
              </div>
              <div v-if="selectedReport.location">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Location</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.location }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Date & Time</p>
                <p class="text-sm font-semibold text-dark-100">{{ new Date(selectedReport.dateTime || selectedReport.startDate || selectedReport.createdAt).toLocaleString() }}</p>
              </div>
              <div v-if="selectedReport.officer">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Reporting Officer</p>
                <div class="flex items-center gap-2">
                  <div class="w-6 h-6 rounded-full bg-primary-500/20 flex items-center justify-center text-[10px] font-bold text-primary-300">
                    {{ selectedReport.officer.firstName?.[0] }}{{ selectedReport.officer.lastName?.[0] }}
                  </div>
                  <p class="text-sm font-semibold text-dark-100">{{ selectedReport.officer.firstName }} {{ selectedReport.officer.lastName }}</p>
                </div>
              </div>
              <div v-if="selectedReport.badgeNumber">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Badge #</p>
                <p class="text-sm font-mono font-semibold text-dark-100">{{ selectedReport.badgeNumber }}</p>
              </div>
            </div>
          </div>

          <!-- Crash-specific info -->
          <div v-if="tab === 'crashes'" class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Crash Details</h4>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div v-if="selectedReport.weather">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Weather</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.weather }}</p>
              </div>
              <div v-if="selectedReport.roadConditions">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Road Conditions</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.roadConditions }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Injuries</p>
                <p class="text-sm font-semibold" :class="selectedReport.injuries ? 'text-red-400' : 'text-green-400'">{{ selectedReport.injuries ? 'YES' : 'None' }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Fatalities</p>
                <p class="text-sm font-semibold" :class="selectedReport.fatalities ? 'text-red-400' : 'text-green-400'">{{ selectedReport.fatalities ? 'YES' : 'None' }}</p>
              </div>
            </div>
          </div>

          <!-- Use of Force specific info -->
          <div v-if="tab === 'use-of-force'" class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Use of Force Details</h4>
            <div class="grid grid-cols-2 gap-4">
              <div v-if="selectedReport.forceType">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Force Type</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.forceType }}</p>
              </div>
              <div v-if="selectedReport.subjectName">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Subject</p>
                <p class="text-sm font-semibold text-dark-100">{{ selectedReport.subjectName }}</p>
              </div>
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Medical Attention</p>
                <p class="text-sm font-semibold" :class="selectedReport.medicalAttention ? 'text-red-400' : 'text-green-400'">{{ selectedReport.medicalAttention ? 'REQUIRED' : 'Not Required' }}</p>
              </div>
            </div>
            <div v-if="selectedReport.witnessInfo" class="mt-4">
              <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Witness Information</p>
              <p class="text-sm text-dark-200">{{ selectedReport.witnessInfo }}</p>
            </div>
          </div>

          <!-- Investigation specific info -->
          <div v-if="tab === 'investigations'" class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-4">Investigation Details</h4>
            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">Priority</p>
                <p class="text-sm font-semibold" :class="{
                  'text-red-400': selectedReport.priority <= 2,
                  'text-yellow-400': selectedReport.priority === 3,
                  'text-blue-400': selectedReport.priority >= 4,
                }">P{{ selectedReport.priority || 3 }}</p>
              </div>
              <div v-if="selectedReport.endDate">
                <p class="text-[10px] text-dark-500 uppercase tracking-wider mb-1">End Date</p>
                <p class="text-sm font-semibold text-dark-100">{{ new Date(selectedReport.endDate).toLocaleDateString() }}</p>
              </div>
            </div>
          </div>

          <!-- Narrative -->
          <div class="glass-card p-5 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-3">{{ tab === 'investigations' ? 'Description' : 'Narrative' }}</h4>
            <div class="bg-dark-800/50 rounded-xl px-4 py-3 border border-white/[0.04]">
              <p class="text-sm text-dark-200 whitespace-pre-wrap leading-relaxed">{{ selectedReport.narrative || selectedReport.description || '—' }}</p>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex items-center justify-between pt-2">
            <div class="flex gap-2">
              <button v-if="selectedReport.status === 'DRAFT' && auth.user?.officer"
                @click="updateStatus(selectedReport, 'SUBMITTED')"
                class="premium-btn-secondary text-xs px-4 py-2">
                Submit for Review
              </button>
              <button v-if="selectedReport.status === 'SUBMITTED' && auth.hasAnyPermission('supervisor', 'admin')"
                @click="updateStatus(selectedReport, 'APPROVED')"
                class="premium-btn-primary text-xs px-4 py-2 bg-gradient-to-r from-green-500 to-emerald-500">
                Approve Report
              </button>
              <button v-if="isAdmin"
                @click="deleteReport(selectedReport.id)"
                class="text-xs px-4 py-2 rounded-xl font-semibold bg-red-500/20 text-red-300 border border-red-500/20 hover:bg-red-500/30 transition-colors">
                🗑️ Delete Report
              </button>
            </div>
            <button @click="showDetail = false" class="premium-btn-secondary px-6">Close</button>
          </div>
        </template>
      </div>
    </div>

    <!-- ==================== CREATE REPORT MODAL ==================== -->
    <div v-if="showCreateModal" class="premium-modal-overlay" @click.self="showCreateModal = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">New {{ activeTabMeta?.label }} Report</h3>
            <p class="text-xs text-dark-400">Fill in the details below</p>
          </div>
        </div>

        <form @submit.prevent="createReport" class="space-y-4">
          <!-- Investigation: Title + Description -->
          <template v-if="tab === 'investigations'">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Title</label>
              <input v-model="newReport.title" class="premium-input" required />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Description</label>
              <textarea v-model="newReport.description" class="premium-input" rows="4" required></textarea>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Start Date</label>
                <input v-model="newReport.dateTime" type="datetime-local" class="premium-input" required />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Priority (1-5)</label>
                <input v-model.number="newReport.priority" type="number" min="1" max="5" class="premium-input" />
              </div>
            </div>
          </template>

          <!-- All other report types -->
          <template v-else>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Location</label>
                <input v-model="newReport.location" class="premium-input" required />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Date / Time</label>
                <input v-model="newReport.dateTime" type="datetime-local" class="premium-input" required />
              </div>
            </div>
            <div v-if="tab === 'incidents'">
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Incident Type</label>
              <input v-model="newReport.type" class="premium-input" placeholder="e.g. ASSAULT, THEFT, BURGLARY" required />
            </div>
            <div v-if="tab === 'use-of-force'" class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Force Type</label>
                <input v-model="newReport.forceType" class="premium-input" placeholder="e.g. TASER, OC SPRAY" required />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Subject Name</label>
                <input v-model="newReport.subjectName" class="premium-input" required />
              </div>
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Narrative</label>
              <textarea v-model="newReport.narrative" class="premium-input" rows="4" required></textarea>
            </div>
            <div v-if="tab === 'crashes'" class="space-y-3">
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Weather</label>
                  <input v-model="newReport.weather" class="premium-input" placeholder="e.g. CLEAR, RAIN" />
                </div>
                <div>
                  <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Road Conditions</label>
                  <input v-model="newReport.roadConditions" class="premium-input" placeholder="e.g. DRY, WET" />
                </div>
              </div>
              <div class="flex gap-4">
                <label class="flex items-center gap-2.5 text-sm text-dark-300 cursor-pointer group/check" @click="newReport.injuries = !newReport.injuries">
                  <div class="w-5 h-5 rounded-md border transition-all flex items-center justify-center"
                    :class="newReport.injuries ? 'bg-primary-500 border-primary-500' : 'border-white/[0.12] bg-white/[0.04]'">
                    <svg v-show="newReport.injuries" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
                  </div>
                  <span class="group-hover/check:text-white transition-colors">Injuries</span>
                </label>
                <label class="flex items-center gap-2.5 text-sm text-dark-300 cursor-pointer group/check" @click="newReport.fatalities = !newReport.fatalities">
                  <div class="w-5 h-5 rounded-md border transition-all flex items-center justify-center"
                    :class="newReport.fatalities ? 'bg-red-500 border-red-500' : 'border-white/[0.12] bg-white/[0.04]'">
                    <svg v-show="newReport.fatalities" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
                  </div>
                  <span class="group-hover/check:text-white transition-colors">Fatalities</span>
                </label>
              </div>
            </div>
            <div v-if="tab === 'use-of-force'" class="space-y-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Witness Info</label>
                <textarea v-model="newReport.witnessInfo" class="premium-input" rows="2"></textarea>
              </div>
              <label class="flex items-center gap-2.5 text-sm text-dark-300 cursor-pointer group/check" @click="newReport.medicalAttention = !newReport.medicalAttention">
                <div class="w-5 h-5 rounded-md border transition-all flex items-center justify-center"
                  :class="newReport.medicalAttention ? 'bg-red-500 border-red-500' : 'border-white/[0.12] bg-white/[0.04]'">
                  <svg v-show="newReport.medicalAttention" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
                </div>
                <span class="group-hover/check:text-white transition-colors">Medical Attention Required</span>
              </label>
            </div>
          </template>

          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateModal = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Create Report</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
