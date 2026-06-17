<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
import api from "@/api/client";
import { getSocket } from "@/api/socket";
import { useAuthStore } from "@/stores/auth";
import { toISODateTime } from "@/utils/dateUtils";

const auth = useAuthStore();
const civilians = ref<any[]>([]);
const loading = ref(false);
const search = ref("");
const selectedCiv = ref<any>(null);
const showDetail = ref(false);
const showCreateModal = ref(false);
const pagination = ref({ page: 1, total: 0, totalPages: 0 });
const activeBolos = ref<any[]>([]);
const createError = ref("");
const detailLoading = ref(false);

// Ticket / Warning / Arrest creation state
const showTicketModal = ref(false);
const showWarningModal = ref(false);
const showArrestModal = ref(false);
const ticketError = ref("");
const warningError = ref("");
const arrestError = ref("");
const ticketSubmitting = ref(false);
const warningSubmitting = ref(false);
const arrestSubmitting = ref(false);

// Confirmation state for inline delete confirmations
const confirmDelete = ref<{ type: 'arrest' | 'citation' | 'warning' | 'civilian'; id: string } | null>(null);

const newTicket = ref({
  violation: "",
  location: "",
  dateTime: "",
  amount: null as number | null,
  description: "",
});

const newWarning = ref({
  type: "",
  description: "",
  location: "",
  dateTime: "",
});

const newArrest = ref({
  location: "",
  dateTime: "",
  narrative: "",
  charges: [""],
  jailTimeDays: null as number | null,
  mirandaRead: false,
});

function resetArrestForm() {
  newArrest.value = { location: "", dateTime: "", narrative: "", charges: [""], jailTimeDays: null, mirandaRead: false };
  arrestError.value = "";
}

function addCharge() {
  newArrest.value.charges.push("");
}

function removeCharge(index: number) {
  newArrest.value.charges.splice(index, 1);
  if (newArrest.value.charges.length === 0) newArrest.value.charges.push("");
}

const commonCharges = [
  "Robbery", "Assault", "Battery", "Burglary", "Theft", "Grand Theft Auto",
  "Drug Possession", "Drug Distribution", "DUI", "Reckless Driving",
  "Weapons Offense", "Murder", "Manslaughter", "Kidnapping",
  "Fraud", "Forgery", "Vandalism", "Trespassing", "Resisting Arrest",
];

async function submitArrest() {
  if (!selectedCiv.value || !auth.user?.officer?.id) return;
  arrestSubmitting.value = true;
  arrestError.value = "";
  try {
    const charges = newArrest.value.charges.filter(c => c.trim());
    if (charges.length === 0) {
      arrestError.value = "At least one charge is required.";
      arrestSubmitting.value = false;
      return;
    }
    await api.post("/criminal/arrests", {
      officerId: auth.user.officer.id,
      civilianId: selectedCiv.value.id,
      location: newArrest.value.location || "Unknown",
      dateTime: toISODateTime(newArrest.value.dateTime),
      narrative: newArrest.value.narrative,
      charges,
      jailTimeDays: newArrest.value.jailTimeDays || undefined,
      mirandaRead: newArrest.value.mirandaRead,
    });
    showArrestModal.value = false;
    resetArrestForm();
    await refreshDetail();
  } catch (err: any) {
    arrestError.value = err?.response?.data?.error || err?.message || "Failed to create arrest report.";
  } finally {
    arrestSubmitting.value = false;
  }
}

// Admin delete functions
const isAdmin = computed(() => auth.hasAnyPermission('admin', 'supervisor'));

function requestDelete(type: 'arrest' | 'citation' | 'warning' | 'civilian', id: string) {
  deleteError.value = '';
  confirmDelete.value = { type, id };
}

function cancelDelete() {
  confirmDelete.value = null;
}

async function confirmDeleteAction() {
  if (!confirmDelete.value) return;
  const { type, id } = confirmDelete.value;
  try {
    if (type === 'arrest') {
      await api.delete(`/criminal/arrests/${id}`);
    } else if (type === 'citation') {
      await api.delete(`/criminal/citations/${id}`);
    } else if (type === 'warning') {
      await api.delete(`/criminal/warnings/${id}`);
    } else if (type === 'civilian') {
      await api.delete(`/civilians/${id}`);
      // Civilian deleted — close modal and refresh list
      showDetail.value = false;
      selectedCiv.value = null;
      fetchCivilians();
      return;
    }
    await refreshDetail();
  } catch (err: any) {
    deleteError.value = err?.response?.data?.error || `Failed to delete ${type}.`;
    setTimeout(() => { deleteError.value = ''; }, 3000);
  } finally {
    confirmDelete.value = null;
  }
}

const deleteError = ref('');

const newCiv = ref({
  firstName: "", lastName: "", dateOfBirth: "",
  gender: "", ethnicity: "", address: "", phone: "",
});

// Common violations for quick-select
const commonViolations = [
  "Speeding", "Running Red Light", "Failure to Yield", "Improper Lane Change",
  "DUI", "Reckless Driving", "No Seatbelt", "Expired Registration",
  "No Insurance", "Illegal U-Turn", "Failure to Signal", "Distracted Driving",
];

const warningTypes = [
  "Verbal Warning", "Written Warning", "Equipment Violation", "Moving Violation",
  "Parking Violation", "Noise Violation", "Trespass Warning",
];

function resetTicketForm() {
  newTicket.value = { violation: "", location: "", dateTime: "", amount: null, description: "" };
  ticketError.value = "";
}

function resetWarningForm() {
  newWarning.value = { type: "", description: "", location: "", dateTime: "" };
  warningError.value = "";
}

async function submitTicket() {
  if (!selectedCiv.value || !auth.user?.officer?.id) return;
  ticketSubmitting.value = true;
  ticketError.value = "";
  try {
    await api.post("/criminal/citations", {
      officerId: auth.user.officer.id,
      civilianId: selectedCiv.value.id,
      violation: newTicket.value.violation,
      location: newTicket.value.location || "Unknown",
      dateTime: toISODateTime(newTicket.value.dateTime),
      amount: newTicket.value.amount || undefined,
      description: newTicket.value.description || undefined,
    });
    showTicketModal.value = false;
    resetTicketForm();
    await refreshDetail();
  } catch (err: any) {
    ticketError.value = err?.response?.data?.error || err?.message || "Failed to create citation.";
  } finally {
    ticketSubmitting.value = false;
  }
}

async function submitWarning() {
  if (!selectedCiv.value || !auth.user?.officer?.id) return;
  warningSubmitting.value = true;
  warningError.value = "";
  try {
    await api.post("/criminal/warnings", {
      officerId: auth.user.officer.id,
      civilianId: selectedCiv.value.id,
      type: newWarning.value.type,
      description: newWarning.value.description,
      location: newWarning.value.location || undefined,
      dateTime: toISODateTime(newWarning.value.dateTime),
    });
    showWarningModal.value = false;
    resetWarningForm();
    await refreshDetail();
  } catch (err: any) {
    warningError.value = err?.response?.data?.error || err?.message || "Failed to create warning.";
  } finally {
    warningSubmitting.value = false;
  }
}

async function refreshDetail() {
  if (!selectedCiv.value) return;
  try {
    const { data } = await api.get(`/civilians/${selectedCiv.value.id}`);
    selectedCiv.value = data;
  } catch { /* silent */ }
}

async function fetchCivilians(page = 1) {
  loading.value = true;
  try {
    const { data } = await api.get("/civilians", {
      params: { page, limit: 25, search: search.value || undefined },
    });
    civilians.value = data.data;
    pagination.value = data.pagination;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function fetchActiveBolos() {
  try {
    const { data } = await api.get("/bolos/active");
    activeBolos.value = data;
  } catch { /* silent */ }
}

function isCivOnBolo(civId: string) {
  return activeBolos.value.some((b: any) => b.targetCivId === civId);
}

function getCivBolos(civId: string) {
  return activeBolos.value.filter((b: any) => b.targetCivId === civId);
}

async function openDetail(id: string) {
  detailLoading.value = true;
  showDetail.value = true;
  try {
    const { data } = await api.get(`/civilians/${id}`);
    selectedCiv.value = data;
  } catch { /* silent */ }
  finally { detailLoading.value = false; }
}

async function createCiv() {
  createError.value = "";
  try {
    const payload = { ...newCiv.value };
    if (payload.dateOfBirth && !payload.dateOfBirth.includes('T')) {
      payload.dateOfBirth = payload.dateOfBirth + 'T00:00:00.000Z';
    }
    await api.post("/civilians", payload);
    showCreateModal.value = false;
    newCiv.value = { firstName: "", lastName: "", dateOfBirth: "", gender: "", ethnicity: "", address: "", phone: "" };
    fetchCivilians();
  } catch (err: any) {
    createError.value = err?.response?.data?.error || err?.message || "Failed to create civilian. Check permissions.";
  }
}

let searchTimer: any;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => fetchCivilians(), 300);
});

onMounted(() => {
  fetchCivilians();
  fetchActiveBolos();
  const socket = getSocket();
  socket.on("civilian:new", fetchCivilians);
  socket.on("bolo:new", fetchActiveBolos);
  socket.on("bolo:update", fetchActiveBolos);
  socket.on("bolo:removed", fetchActiveBolos);
});

onUnmounted(() => {
  const socket = getSocket();
  socket.off("civilian:new", fetchCivilians);
  socket.off("bolo:new", fetchActiveBolos);
  socket.off("bolo:update", fetchActiveBolos);
  socket.off("bolo:removed", fetchActiveBolos);
});
</script>

<template>
  <div class="p-6 space-y-6 max-w-[1400px] mx-auto">
    <!-- Header -->
    <div class="flex items-start justify-between">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <div class="w-1 h-8 rounded-full gradient-accent"></div>
          <h2 class="text-2xl font-bold text-white tracking-tight">Civilian Database</h2>
        </div>
        <p class="text-sm text-dark-400 ml-[1.1rem]">Search, view, and manage civilian records</p>
      </div>
      <button @click="showCreateModal = true" class="premium-btn-primary">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
        New Civilian
      </button>
    </div>

    <!-- Search -->
    <div class="glass-card p-4">
      <div class="flex gap-3 items-center">
        <div class="relative flex-1 max-w-md">
          <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-dark-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
          <input v-model="search" class="premium-input pl-10" placeholder="Search by name, phone, address..." />
        </div>
        <span class="text-xs text-dark-500">{{ pagination.total || 0 }} records</span>
      </div>
    </div>

    <!-- Table -->
    <div class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Name</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">DOB</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Phone</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Address</th>
            <th v-if="isAdmin" class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Player</th>
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
          <tr v-else-if="!civilians.length">
            <td colspan="7" class="px-5 py-16 text-center">
              <div class="text-5xl mb-4 opacity-40">👤</div>
              <p class="text-dark-400 font-medium">No civilians found</p>
              <p class="text-dark-500 text-xs mt-1">Try a different search or create a new record</p>
            </td>
          </tr>
          <tr
            v-for="civ in civilians"
            :key="civ.id"
            class="premium-table-row cursor-pointer group"
            @click="openDetail(civ.id)"
          >
            <td class="px-5 py-4">
              <div class="flex items-center gap-3">
                <div class="w-8 h-8 rounded-full bg-primary-500/20 flex items-center justify-center text-[11px] font-bold text-primary-300 flex-shrink-0">
                  {{ civ.firstName?.[0] }}{{ civ.lastName?.[0] }}
                </div>
                <span class="font-medium text-dark-100 group-hover:text-white transition-colors">{{ civ.firstName }} {{ civ.lastName }}</span>
              </div>
            </td>
            <td class="px-5 py-4 text-dark-300 text-xs">{{ new Date(civ.dateOfBirth).toLocaleDateString() }}</td>
            <td class="px-5 py-4 text-dark-300 text-xs font-mono">{{ civ.phone || "—" }}</td>
            <td class="px-5 py-4 text-dark-400 text-xs truncate max-w-[200px]">{{ civ.address || "—" }}</td>
            <td v-if="isAdmin" class="px-5 py-4">
              <span v-if="civ.playerIdentifier" class="premium-badge bg-purple-500/15 text-purple-300 ring-1 ring-purple-500/20 text-[10px]">{{ civ.playerIdentifier }}</span>
              <span v-else class="text-dark-500 text-[10px]">—</span>
            </td>
            <td class="px-5 py-4">
              <div class="flex gap-1.5 flex-wrap">
                <span v-if="isCivOnBolo(civ.id)" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse">BOLO</span>
                <span v-if="civ.warrants?.length" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20">Warrant</span>
                <span v-for="v in civ.vehicles?.filter((x: any) => x.stolen)" :key="v.plate" class="premium-badge bg-orange-500/15 text-orange-300 ring-1 ring-orange-500/20">Stolen Vehicle</span>
                <span v-if="civ._citationCount > 0" class="premium-badge bg-yellow-500/15 text-yellow-300 ring-1 ring-yellow-500/20">{{ civ._citationCount }} Ticket{{ civ._citationCount > 1 ? 's' : '' }}</span>
                <span v-if="civ._warningCount > 0" class="premium-badge bg-blue-500/15 text-blue-300 ring-1 ring-blue-500/20">{{ civ._warningCount }} Warning{{ civ._warningCount > 1 ? 's' : '' }}</span>
              </div>
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
      <button @click="fetchCivilians(pagination.page - 1)" :disabled="pagination.page <= 1" class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">← Previous</button>
      <span class="text-sm text-dark-400">Page {{ pagination.page }} of {{ pagination.totalPages }}</span>
      <button @click="fetchCivilians(pagination.page + 1)" :disabled="pagination.page >= pagination.totalPages" class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">Next →</button>
    </div>

    <!-- ==================== DETAIL MODAL ==================== -->
    <div v-if="showDetail && selectedCiv" class="premium-modal-overlay" @click.self="showDetail = false">
      <div class="premium-modal-content max-w-3xl">
        <!-- Loading state -->
        <div v-if="detailLoading" class="space-y-4 py-8">
          <div v-for="i in 4" :key="i" class="h-16 rounded-xl shimmer-loading"></div>
        </div>

        <template v-else>
          <!-- Header -->
          <div class="flex items-start justify-between mb-6">
            <div class="flex items-center gap-4">
              <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-primary-500/30 to-purple-500/30 flex items-center justify-center text-xl font-bold text-white border border-white/[0.08]">
                {{ selectedCiv.firstName?.[0] }}{{ selectedCiv.lastName?.[0] }}
              </div>
              <div>
                <h3 class="text-xl font-bold text-white">{{ selectedCiv.firstName }} {{ selectedCiv.lastName }}</h3>
                <div class="flex gap-2 mt-1.5">
                  <span v-if="isCivOnBolo(selectedCiv.id)" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 animate-pulse text-[10px]">⚠️ ACTIVE BOLO</span>
                  <span v-if="selectedCiv.warrants?.length" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 text-[10px]">{{ selectedCiv.warrants.length }} WARRANT{{ selectedCiv.warrants.length > 1 ? 'S' : '' }}</span>
                </div>
              </div>
            </div>
            <button @click="showDetail = false" class="premium-btn-secondary text-xs px-3 py-1.5">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>

          <!-- Quick Stats -->
          <div class="grid grid-cols-4 gap-3 mb-6">
            <div class="glass-card p-3 text-center hover:border-red-500/20 transition-colors">
              <p class="text-2xl font-bold" :class="selectedCiv.arrests?.length ? 'text-red-400' : 'text-green-400'">{{ selectedCiv.arrests?.length || 0 }}</p>
              <p class="text-[10px] text-dark-400 uppercase tracking-wider mt-1">Arrests</p>
            </div>
            <div class="glass-card p-3 text-center hover:border-yellow-500/20 transition-colors">
              <p class="text-2xl font-bold" :class="selectedCiv.citations?.length ? 'text-yellow-400' : 'text-green-400'">{{ selectedCiv.citations?.length || 0 }}</p>
              <p class="text-[10px] text-dark-400 uppercase tracking-wider mt-1">Tickets</p>
            </div>
            <div class="glass-card p-3 text-center hover:border-blue-500/20 transition-colors">
              <p class="text-2xl font-bold" :class="selectedCiv.warnings?.length ? 'text-blue-400' : 'text-green-400'">{{ selectedCiv.warnings?.length || 0 }}</p>
              <p class="text-[10px] text-dark-400 uppercase tracking-wider mt-1">Warnings</p>
            </div>
            <div class="glass-card p-3 text-center hover:border-primary-500/20 transition-colors">
              <p class="text-2xl font-bold" :class="selectedCiv.vehicles?.length ? 'text-dark-100' : 'text-dark-500'">{{ selectedCiv.vehicles?.length || 0 }}</p>
              <p class="text-[10px] text-dark-400 uppercase tracking-wider mt-1">Vehicles</p>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="flex gap-2 mb-6 flex-wrap">
            <button @click="resetTicketForm(); showTicketModal = true" class="premium-btn-primary text-xs px-4 py-2">
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
              Write Ticket
            </button>
            <button @click="resetWarningForm(); showWarningModal = true" class="premium-btn-secondary text-xs px-4 py-2">
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>
              Write Warning
            </button>
            <button @click="resetArrestForm(); showArrestModal = true" class="text-xs px-4 py-2 rounded-xl font-semibold transition-all duration-200 bg-red-500/20 text-red-300 border border-red-500/20 hover:bg-red-500/30">
              <svg class="w-3.5 h-3.5 inline mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>
              File Arrest
            </button>
          </div>

          <!-- Personal Info -->
          <div class="glass-card p-4 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-3">Personal Information</h4>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div><span class="text-dark-500 text-xs">Date of Birth</span><p class="text-dark-100 font-medium">{{ new Date(selectedCiv.dateOfBirth).toLocaleDateString() }}</p></div>
              <div><span class="text-dark-500 text-xs">Gender</span><p class="text-dark-100 font-medium">{{ selectedCiv.gender || "—" }}</p></div>
              <div><span class="text-dark-500 text-xs">Phone</span><p class="text-dark-100 font-medium font-mono">{{ selectedCiv.phone || "—" }}</p></div>
              <div><span class="text-dark-500 text-xs">Address</span><p class="text-dark-100 font-medium">{{ selectedCiv.address || "—" }}</p></div>
              <div v-if="isAdmin && selectedCiv.playerIdentifier"><span class="text-dark-500 text-xs">FiveM Player</span><p class="text-dark-100 font-medium font-mono">{{ selectedCiv.playerIdentifier }}</p></div>
            </div>
          </div>

          <!-- Licenses -->
          <div v-if="selectedCiv.licenses?.length" class="glass-card p-4 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-3">Licenses</h4>
            <div class="flex gap-2 flex-wrap">
              <span v-for="l in selectedCiv.licenses" :key="l.id" class="premium-badge"
                :class="l.status === 'VALID' ? 'bg-green-500/15 text-green-300 ring-1 ring-green-500/20' : l.status === 'SUSPENDED' ? 'bg-red-500/15 text-red-300 ring-1 ring-red-500/20' : 'bg-yellow-500/15 text-yellow-300 ring-1 ring-yellow-500/20'">
                {{ l.type }} — {{ l.status }}
              </span>
            </div>
          </div>

          <!-- Vehicles -->
          <div v-if="selectedCiv.vehicles?.length" class="glass-card p-4 mb-4">
            <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest mb-3">Registered Vehicles</h4>
            <div class="space-y-2">
              <div v-for="v in selectedCiv.vehicles" :key="v.id" class="bg-dark-700/50 rounded-xl px-4 py-3 flex items-center gap-4 border border-white/[0.04] hover:border-white/[0.08] transition-colors">
                <div class="w-10 h-10 rounded-lg bg-dark-600/50 flex items-center justify-center text-lg">🚗</div>
                <div class="flex-1">
                  <div class="flex items-center gap-2">
                    <span class="font-mono font-semibold text-dark-100">{{ v.plate }}</span>
                    <span v-if="v.stolen" class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 text-[10px] animate-pulse">STOLEN</span>
                  </div>
                  <p class="text-xs text-dark-400">{{ v.color }} {{ v.model }} {{ v.year ? `(${v.year})` : '' }}</p>
                </div>
                <div class="text-right text-xs text-dark-500">
                  <p v-if="v.registrationStatus">{{ v.registrationStatus }}</p>
                </div>
              </div>
            </div>
          </div>

          <!-- BOLOs -->
          <div v-if="isCivOnBolo(selectedCiv.id)" class="glass-card p-4 mb-4 border-red-500/20">
            <h4 class="text-xs font-semibold text-red-400 uppercase tracking-widest mb-3">🚨 Active BOLOs</h4>
            <div v-for="b in getCivBolos(selectedCiv.id)" :key="b.id" class="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 mb-2">
              <div class="flex items-center gap-2 mb-1">
                <span class="premium-badge bg-red-500/20 text-red-300 text-[10px]">{{ b.type }}</span>
                <span class="text-xs text-red-300 font-medium">{{ b.priority }}</span>
              </div>
              <p class="text-sm text-red-200">{{ b.description }}</p>
              <p v-if="b.lastKnownLocation" class="text-xs text-red-400/60 mt-1">📍 {{ b.lastKnownLocation }}</p>
            </div>
          </div>

          <!-- Warrants -->
          <div v-if="selectedCiv.warrants?.length" class="glass-card p-4 mb-4 border-red-500/20">
            <h4 class="text-xs font-semibold text-red-400 uppercase tracking-widest mb-3">⚠️ Active Warrants</h4>
            <div v-for="w in selectedCiv.warrants" :key="w.id" class="bg-red-500/10 border border-red-500/20 rounded-xl px-4 py-3 mb-2">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm text-red-200 font-medium">{{ w.type }}</p>
                  <p class="text-xs text-red-300/70">{{ w.charges }}</p>
                </div>
                <span class="text-xs text-dark-500">{{ new Date(w.issuedAt).toLocaleDateString() }}</span>
              </div>
            </div>
          </div>

          <!-- Citations / Tickets -->
          <div class="glass-card p-4 mb-4">
            <div class="flex items-center justify-between mb-3">
              <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest">📝 Citations &amp; Tickets</h4>
              <button v-if="auth.user?.officer" @click="resetTicketForm(); showTicketModal = true" class="text-[10px] text-primary-400 hover:text-primary-300 font-medium transition-colors">+ Write Ticket</button>
            </div>
            <div v-if="!selectedCiv.citations?.length" class="text-center py-6 text-dark-500 text-sm">No citations on record</div>
            <div v-else class="space-y-2">
              <div v-for="c in selectedCiv.citations" :key="c.id" class="bg-yellow-500/5 border border-yellow-500/10 rounded-xl px-4 py-3">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="text-sm text-yellow-200 font-medium">{{ c.violation }}</p>
                    <p class="text-xs text-dark-400 mt-0.5 font-mono">{{ c.citationNumber || '—' }}</p>
                  </div>
                  <div class="flex items-center gap-2">
                    <div class="text-right">
                      <p v-if="c.amount" class="text-sm font-bold text-yellow-300">${{ Number(c.amount).toLocaleString() }}</p>
                    </div>
                    <button v-if="isAdmin" @click="requestDelete('citation', c.id)" class="px-2 py-1 rounded-lg text-xs text-red-400 hover:bg-red-500/10 transition-colors" title="Delete Citation">✕</button>
                  </div>
                </div>
                <div class="flex items-center justify-between mt-2 text-xs text-dark-500">
                  <span>📍 {{ c.location || '—' }}</span>
                  <span>{{ new Date(c.dateTime).toLocaleDateString() }}</span>
                  <span>Officer: {{ c.officer?.firstName }} {{ c.officer?.lastName }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Written Warnings -->
          <div class="glass-card p-4 mb-4">
            <div class="flex items-center justify-between mb-3">
              <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest">⚠️ Written Warnings</h4>
              <button v-if="auth.user?.officer" @click="resetWarningForm(); showWarningModal = true" class="text-[10px] text-primary-400 hover:text-primary-300 font-medium transition-colors">+ Write Warning</button>
            </div>
            <div v-if="!selectedCiv.warnings?.length" class="text-center py-6 text-dark-500 text-sm">No warnings on record</div>
            <div v-else class="space-y-2">
              <div v-for="w in selectedCiv.warnings" :key="w.id" class="bg-blue-500/5 border border-blue-500/10 rounded-xl px-4 py-3">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="text-sm text-blue-200 font-medium">{{ w.type }}</p>
                    <p class="text-xs text-dark-400 mt-0.5">{{ w.description || '—' }}</p>
                  </div>
                  <button v-if="isAdmin" @click="requestDelete('warning', w.id)" class="px-2 py-1 rounded-lg text-xs text-red-400 hover:bg-red-500/10 transition-colors" title="Delete Warning">✕</button>
                </div>
                <div class="flex items-center justify-between mt-2 text-xs text-dark-500">
                  <span v-if="w.location">📍 {{ w.location }}</span>
                  <span>{{ new Date(w.dateTime).toLocaleDateString() }}</span>
                  <span>Officer: {{ w.officer?.firstName }} {{ w.officer?.lastName }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Arrest History -->
          <div class="glass-card p-4 mb-4">
            <div class="flex items-center justify-between mb-3">
              <h4 class="text-xs font-semibold text-dark-400 uppercase tracking-widest">🔒 Arrest History</h4>
              <button v-if="auth.user?.officer" @click="resetArrestForm(); showArrestModal = true" class="text-[10px] text-red-400 hover:text-red-300 font-medium transition-colors">+ File Arrest</button>
            </div>
            <div v-if="!selectedCiv.arrests?.length" class="text-center py-6 text-dark-500 text-sm">No arrest history</div>
            <div class="space-y-2">
              <div v-for="a in selectedCiv.arrests" :key="a.id" class="bg-dark-700/50 rounded-xl px-4 py-3 border border-white/[0.04]">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm text-dark-100 font-medium">{{ a.reportNumber }}</p>
                    <p class="text-xs text-dark-400 mt-0.5">{{ a.location }}</p>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="premium-badge bg-red-500/15 text-red-300 ring-1 ring-red-500/20 text-[10px]">ARREST</span>
                    <button v-if="isAdmin" @click="requestDelete('arrest', a.id)" class="px-2 py-1 rounded-lg text-xs text-red-400 hover:bg-red-500/10 transition-colors" title="Delete Arrest Report">✕</button>
                  </div>
                </div>
                <div class="flex items-center justify-between mt-2 text-xs text-dark-500">
                  <span>{{ new Date(a.dateTime).toLocaleDateString() }}</span>
                  <span>Officer: {{ a.officer?.firstName }} {{ a.officer?.lastName }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Delete Error Banner -->
          <div v-if="deleteError" class="mb-4 text-xs text-red-400 bg-red-500/10 rounded-xl px-4 py-3 border border-red-500/20">{{ deleteError }}</div>

          <!-- Admin: Delete Civilian -->
          <div v-if="isAdmin" class="glass-card p-4 mb-4 border-red-500/20">
            <div class="flex items-center justify-between">
              <div>
                <h4 class="text-xs font-semibold text-red-400 uppercase tracking-widest">Danger Zone</h4>
                <p class="text-xs text-dark-500 mt-1">Deleting this civilian will remove them from the database. This action cannot be undone.</p>
              </div>
              <button @click="requestDelete('civilian', selectedCiv.id)" class="px-4 py-2 rounded-xl text-xs font-semibold bg-red-500/20 text-red-300 border border-red-500/30 hover:bg-red-500/30 transition-colors">
                Delete Civilian
              </button>
            </div>
          </div>

          <!-- Close -->
          <div class="flex justify-end pt-2">
            <button @click="showDetail = false" class="premium-btn-secondary px-6">Close</button>
          </div>
        </template>
      </div>
    </div>

    <!-- ==================== TICKET MODAL ==================== -->
    <div v-if="showTicketModal" class="premium-modal-overlay" @click.self="showTicketModal = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-yellow-500 to-orange-500 flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">Write Citation</h3>
            <p class="text-xs text-dark-400">Issuing to {{ selectedCiv?.firstName }} {{ selectedCiv?.lastName }}</p>
          </div>
        </div>

        <form @submit.prevent="submitTicket" class="space-y-4">
          <div v-if="ticketError" class="text-xs text-red-400 bg-red-500/10 rounded-xl px-4 py-3 border border-red-500/20">{{ ticketError }}</div>

          <!-- Quick Violation Select -->
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Common Violations</label>
            <div class="flex gap-1.5 flex-wrap">
              <button v-for="v in commonViolations" :key="v" type="button"
                @click="newTicket.violation = v"
                class="px-3 py-1.5 rounded-lg text-[11px] font-medium transition-all duration-200"
                :class="newTicket.violation === v ? 'bg-primary-500 text-white shadow-lg shadow-primary-500/30' : 'bg-dark-700/50 text-dark-300 hover:bg-dark-600/50 hover:text-dark-100 border border-white/[0.04]'">
                {{ v }}
              </button>
            </div>
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Violation</label>
            <input v-model="newTicket.violation" class="premium-input" placeholder="e.g. Speeding 65 in a 45" required />
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Location</label>
              <input v-model="newTicket.location" class="premium-input" placeholder="e.g. Main St & 5th Ave" />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Fine Amount ($)</label>
              <input v-model.number="newTicket.amount" type="number" min="0" step="0.01" class="premium-input" placeholder="0.00" />
            </div>
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Date & Time</label>
            <input v-model="newTicket.dateTime" type="datetime-local" class="premium-input" />
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Additional Notes</label>
            <textarea v-model="newTicket.description" class="premium-input" rows="2" placeholder="Optional notes..."></textarea>
          </div>

          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showTicketModal = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" :disabled="ticketSubmitting" class="premium-btn-primary px-6">
              {{ ticketSubmitting ? 'Issuing...' : 'Issue Citation' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- ==================== WARNING MODAL ==================== -->
    <div v-if="showWarningModal" class="premium-modal-overlay" @click.self="showWarningModal = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">Write Warning</h3>
            <p class="text-xs text-dark-400">Issuing to {{ selectedCiv?.firstName }} {{ selectedCiv?.lastName }}</p>
          </div>
        </div>

        <form @submit.prevent="submitWarning" class="space-y-4">
          <div v-if="warningError" class="text-xs text-red-400 bg-red-500/10 rounded-xl px-4 py-3 border border-red-500/20">{{ warningError }}</div>

          <!-- Quick Type Select -->
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Warning Type</label>
            <div class="flex gap-1.5 flex-wrap">
              <button v-for="t in warningTypes" :key="t" type="button"
                @click="newWarning.type = t"
                class="px-3 py-1.5 rounded-lg text-[11px] font-medium transition-all duration-200"
                :class="newWarning.type === t ? 'bg-primary-500 text-white shadow-lg shadow-primary-500/30' : 'bg-dark-700/50 text-dark-300 hover:bg-dark-600/50 hover:text-dark-100 border border-white/[0.04]'">
                {{ t }}
              </button>
            </div>
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Description</label>
            <textarea v-model="newWarning.description" class="premium-input" rows="3" placeholder="Describe the reason for this warning..." required></textarea>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Location</label>
              <input v-model="newWarning.location" class="premium-input" placeholder="e.g. Main St" />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Date & Time</label>
              <input v-model="newWarning.dateTime" type="datetime-local" class="premium-input" />
            </div>
          </div>

          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showWarningModal = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" :disabled="warningSubmitting" class="premium-btn-primary px-6">
              {{ warningSubmitting ? 'Issuing...' : 'Issue Warning' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- ==================== ARREST MODAL ==================== -->
    <div v-if="showArrestModal" class="premium-modal-overlay" @click.self="showArrestModal = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-red-500 to-red-700 flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">File Arrest Report</h3>
            <p class="text-xs text-dark-400">Arresting {{ selectedCiv?.firstName }} {{ selectedCiv?.lastName }}</p>
          </div>
        </div>

        <form @submit.prevent="submitArrest" class="space-y-4">
          <div v-if="arrestError" class="text-xs text-red-400 bg-red-500/10 rounded-xl px-4 py-3 border border-red-500/20">{{ arrestError }}</div>

          <!-- Charges -->
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Charges</label>
            <div class="flex gap-1.5 flex-wrap mb-2">
              <button v-for="c in commonCharges" :key="c" type="button"
                @click="if (!newArrest.charges.includes(c)) { const lastIdx = newArrest.charges.length - 1; if (newArrest.charges[lastIdx] === '') { newArrest.charges[lastIdx] = c; } else { newArrest.charges.push(c); } }"
                class="px-2.5 py-1 rounded-lg text-[10px] font-medium transition-all duration-200"
                :class="newArrest.charges.includes(c) ? 'bg-red-500 text-white shadow-lg shadow-red-500/30' : 'bg-dark-700/50 text-dark-300 hover:bg-dark-600/50 hover:text-dark-100 border border-white/[0.04]'">
                {{ c }}
              </button>
            </div>
            <div class="space-y-2">
              <div v-for="(_, idx) in newArrest.charges" :key="idx" class="flex gap-2">
                <input v-model="newArrest.charges[idx]" class="premium-input flex-1" placeholder="Charge description..." required />
                <button type="button" @click="removeCharge(idx)" class="premium-btn-secondary text-xs px-2" v-if="newArrest.charges.length > 1">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
                </button>
              </div>
            </div>
            <button type="button" @click="addCharge" class="text-[10px] text-primary-400 hover:text-primary-300 font-medium mt-2 transition-colors">+ Add Another Charge</button>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Location</label>
              <input v-model="newArrest.location" class="premium-input" placeholder="e.g. Main St & 5th Ave" />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Date & Time</label>
              <input v-model="newArrest.dateTime" type="datetime-local" class="premium-input" />
            </div>
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Jail Time (Days)</label>
            <input v-model.number="newArrest.jailTimeDays" type="number" min="0" class="premium-input" placeholder="0" />
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Narrative</label>
            <textarea v-model="newArrest.narrative" class="premium-input" rows="3" placeholder="Describe the circumstances of the arrest..." required></textarea>
          </div>

          <label class="flex items-center gap-2.5 text-sm text-dark-300 cursor-pointer group/check" @click="newArrest.mirandaRead = !newArrest.mirandaRead">
            <div class="w-5 h-5 rounded-md border transition-all flex items-center justify-center"
              :class="newArrest.mirandaRead ? 'bg-primary-500 border-primary-500' : 'border-white/[0.12] bg-white/[0.04]'">
              <svg v-show="newArrest.mirandaRead" class="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>
            </div>
            <span class="group-hover/check:text-white transition-colors">Miranda Rights Read</span>
          </label>

          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showArrestModal = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" :disabled="arrestSubmitting" class="px-6 py-2 rounded-xl font-semibold text-white transition-all duration-200 bg-gradient-to-r from-red-500 to-red-700 hover:from-red-400 hover:to-red-600 shadow-lg shadow-red-500/20">
              {{ arrestSubmitting ? 'Filing...' : 'File Arrest' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- ==================== DELETE CONFIRMATION MODAL ==================== -->
    <div v-if="confirmDelete" class="premium-modal-overlay" @click.self="cancelDelete">
      <div class="premium-modal-content max-w-sm">
        <div class="text-center">
          <div class="w-14 h-14 rounded-2xl bg-red-500/20 flex items-center justify-center mx-auto mb-4">
            <svg class="w-7 h-7 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
          </div>
          <h3 class="text-lg font-bold text-white mb-2">Confirm Deletion</h3>
          <p v-if="confirmDelete.type === 'civilian'" class="text-sm text-dark-400 mb-1">Are you sure you want to delete this civilian?</p>
          <p v-else-if="confirmDelete.type === 'arrest'" class="text-sm text-dark-400 mb-1">Are you sure you want to delete this arrest report?</p>
          <p v-else-if="confirmDelete.type === 'citation'" class="text-sm text-dark-400 mb-1">Are you sure you want to delete this citation?</p>
          <p v-else-if="confirmDelete.type === 'warning'" class="text-sm text-dark-400 mb-1">Are you sure you want to delete this warning?</p>
          <p class="text-xs text-dark-500 mb-6">This action cannot be undone.</p>
          <div class="flex gap-3 justify-center">
            <button @click="cancelDelete" class="premium-btn-secondary px-6">Cancel</button>
            <button @click="confirmDeleteAction" class="px-6 py-2.5 rounded-xl text-sm font-semibold bg-red-500 text-white hover:bg-red-400 transition-colors shadow-lg shadow-red-500/20">Delete</button>
          </div>
        </div>
      </div>
    </div>

    <!-- ==================== CREATE CIVILIAN MODAL ==================== -->
    <div v-if="showCreateModal" class="premium-modal-overlay" @click.self="showCreateModal = false; createError = ''">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">New Civilian</h3>
            <p class="text-xs text-dark-400">Register a new person in the database</p>
          </div>
        </div>

        <form @submit.prevent="createCiv" class="space-y-4">
          <div v-if="createError" class="text-xs text-red-400 bg-red-500/10 rounded-xl px-4 py-3 border border-red-500/20">{{ createError }}</div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">First Name</label><input v-model="newCiv.firstName" class="premium-input" required /></div>
            <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Last Name</label><input v-model="newCiv.lastName" class="premium-input" required /></div>
          </div>
          <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Date of Birth</label><input v-model="newCiv.dateOfBirth" type="date" class="premium-input" required /></div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Gender</label><input v-model="newCiv.gender" class="premium-input" /></div>
            <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Phone</label><input v-model="newCiv.phone" class="premium-input" /></div>
          </div>
          <div><label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Address</label><input v-model="newCiv.address" class="premium-input" /></div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateModal = false; createError = ''" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Create Civilian</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
