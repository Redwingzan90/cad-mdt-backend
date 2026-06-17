<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useDispatchStore, type DispatchCall } from "@/stores/dispatch";
import { useAuthStore } from "@/stores/auth";
import api from "@/api/client";

const dispatchStore = useDispatchStore();
const authStore = useAuthStore();

const showCreateModal = ref(false);
const selectedCall = ref<DispatchCall | null>(null);
const showCallDetail = ref(false);
const newNote = ref("");

// Create call form
const newCall = ref({
  type: "",
  description: "",
  location: "",
  priority: "PRIORITY_3",
  departmentId: "",
});

const departments = ref<any[]>([]);
const officers = ref<any[]>([]);

const priorityConfig: Record<string, { label: string; class: string; dot: string }> = {
  PRIORITY_1: { label: "Priority 1 — Emergency", class: "bg-red-500/20 text-red-400 border-red-500/40", dot: "bg-red-500" },
  PRIORITY_2: { label: "Priority 2 — Urgent", class: "bg-orange-500/20 text-orange-400 border-orange-500/40", dot: "bg-orange-500" },
  PRIORITY_3: { label: "Priority 3 — Normal", class: "bg-yellow-500/20 text-yellow-400 border-yellow-500/40", dot: "bg-yellow-500" },
  PRIORITY_4: { label: "Priority 4 — Low", class: "bg-blue-500/20 text-blue-400 border-blue-500/40", dot: "bg-blue-500" },
};

const statusConfig: Record<string, string> = {
  PENDING: "badge-warning",
  ASSIGNED: "badge-info",
  EN_ROUTE: "badge-purple",
  ON_SCENE: "badge-success",
};

const sortedCalls = computed(() => {
  const order: Record<string, number> = { PRIORITY_1: 0, PRIORITY_2: 1, PRIORITY_3: 2, PRIORITY_4: 3 };
  return [...dispatchStore.activeCalls].sort(
    (a, b) => (order[a.priority] ?? 9) - (order[b.priority] ?? 9)
  );
});

async function fetchMeta() {
  try {
    const [deptRes, officerRes] = await Promise.all([
      api.get("/departments"),
      api.get("/officers/on-duty"),
    ]);
    departments.value = deptRes.data;
    officers.value = officerRes.data;
    if (departments.value.length && !newCall.value.departmentId) {
      newCall.value.departmentId = departments.value[0].id;
    }
  } catch { /* silent */ }
}

async function createCall() {
  try {
    await dispatchStore.createCall(newCall.value);
    showCreateModal.value = false;
    newCall.value = { type: "", description: "", location: "", priority: "PRIORITY_3", departmentId: departments.value[0]?.id || "" };
  } catch { /* silent */ }
}

function openCallDetail(call: DispatchCall) {
  selectedCall.value = call;
  showCallDetail.value = true;
}

async function updateCallStatus(callId: string, status: string) {
  try {
    await dispatchStore.updateCall(callId, { status } as any);
  } catch { /* silent */ }
}

async function assignOfficerToCall(officerId: string) {
  if (!selectedCall.value) return;
  try {
    await dispatchStore.assignOfficer(selectedCall.value.id, officerId);
  } catch { /* silent */ }
}

async function unassignOfficerFromCall(officerId: string) {
  if (!selectedCall.value) return;
  try {
    await dispatchStore.unassignOfficer(selectedCall.value.id, officerId);
  } catch { /* silent */ }
}

async function addNote() {
  if (!selectedCall.value || !newNote.value.trim()) return;
  try {
    await dispatchStore.addCallNote(selectedCall.value.id, newNote.value.trim());
    newNote.value = "";
  } catch { /* silent */ }
}

onMounted(() => {
  dispatchStore.fetchActiveCalls();
  dispatchStore.fetchEmergencyCalls();
  dispatchStore.initSocketListeners();
  fetchMeta();
});
</script>

<template>
  <div class="p-4 space-y-4">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <h2 class="text-lg font-bold text-white">Active Dispatch</h2>
      <button
        v-if="authStore.hasPermission('dispatch')"
        @click="showCreateModal = true"
        class="btn-primary"
      >
        + New Call
      </button>
    </div>

    <!-- 911 Calls Banner -->
    <div v-if="dispatchStore.emergencyCalls.length" class="space-y-2">
      <div
        v-for="ecall in dispatchStore.emergencyCalls"
        :key="ecall.id"
        class="card border-l-4 border-l-red-500 bg-red-500/5 p-3 flex items-center gap-4"
      >
        <div class="flex-shrink-0 text-2xl">📞</div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-red-400">911 — {{ ecall.type }}</p>
          <p class="text-xs text-dark-300 truncate">{{ ecall.description }}</p>
          <p class="text-xs text-dark-500">{{ ecall.callerName }} • {{ ecall.location }}</p>
        </div>
        <div class="flex gap-2">
          <button
            v-if="authStore.hasPermission('dispatch')"
            @click="() => {
              newCall.type = ecall.type;
              newCall.description = ecall.description;
              newCall.location = ecall.location;
              newCall.priority = 'PRIORITY_1';
              showCreateModal = true;
            }"
            class="btn-sm btn-primary"
          >
            Dispatch
          </button>
        </div>
      </div>
    </div>

    <!-- Active Calls Grid -->
    <div v-if="dispatchStore.loading" class="text-center py-12 text-dark-500">Loading calls...</div>
    <div v-else-if="!sortedCalls.length" class="text-center py-12 text-dark-500">
      <div class="text-4xl mb-3">✅</div>
      <p>No active calls</p>
    </div>
    <div v-else class="space-y-2">
      <div
        v-for="call in sortedCalls"
        :key="call.id"
        @click="openCallDetail(call)"
        class="card p-4 cursor-pointer hover:bg-dark-700/50 transition-colors border-l-4"
        :class="priorityConfig[call.priority]?.dot.replace('bg-', 'border-l-')"
      >
        <div class="flex items-start gap-3">
          <span
            class="text-xs font-bold px-2 py-1 rounded border min-w-[36px] text-center flex-shrink-0 mt-0.5"
            :class="priorityConfig[call.priority]?.class"
          >
            {{ call.priority.replace("PRIORITY_", "P") }}
          </span>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="text-sm font-semibold text-dark-100">{{ call.type }}</span>
              <span class="text-xs" :class="statusConfig[call.status]">{{ call.status.replace(/_/g, " ") }}</span>
            </div>
            <p class="text-xs text-dark-300 mb-1">📍 {{ call.location }}</p>
            <p class="text-xs text-dark-400 line-clamp-1">{{ call.description }}</p>
            <div v-if="call.assignments?.length" class="flex gap-1.5 mt-2 flex-wrap">
              <span
                v-for="a in call.assignments.filter(x => !x.clearedAt)"
                :key="a.id"
                class="badge-info text-[10px]"
              >
                {{ a.officer.callsign || `${a.officer.firstName} ${a.officer.lastName[0]}` }}
              </span>
            </div>
          </div>
          <div class="text-right flex-shrink-0">
            <p class="text-xs text-dark-500 font-mono">{{ call.callNumber }}</p>
            <p class="text-[10px] text-dark-600">
              {{ new Date(call.createdAt).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" }) }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Create Call Modal -->
    <div v-if="showCreateModal" class="modal-overlay" @click.self="showCreateModal = false">
      <div class="modal-content max-w-xl">
        <h3 class="text-lg font-bold text-white mb-4">Create Dispatch Call</h3>
        <form @submit.prevent="createCall" class="space-y-4">
          <div>
            <label class="text-sm text-dark-300 mb-1 block">Call Type</label>
            <input v-model="newCall.type" class="input" placeholder="e.g., Traffic Stop, Robbery" required />
          </div>
          <div>
            <label class="text-sm text-dark-300 mb-1 block">Location</label>
            <input v-model="newCall.location" class="input" placeholder="e.g., Vinewood Blvd & Alta St" required />
          </div>
          <div>
            <label class="text-sm text-dark-300 mb-1 block">Description</label>
            <textarea v-model="newCall.description" class="input" rows="3" placeholder="Describe the situation..." required />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-sm text-dark-300 mb-1 block">Priority</label>
              <select v-model="newCall.priority" class="select">
                <option value="PRIORITY_1">🔴 Priority 1 — Emergency</option>
                <option value="PRIORITY_2">🟠 Priority 2 — Urgent</option>
                <option value="PRIORITY_3">🟡 Priority 3 — Normal</option>
                <option value="PRIORITY_4">🔵 Priority 4 — Low</option>
              </select>
            </div>
            <div>
              <label class="text-sm text-dark-300 mb-1 block">Department</label>
              <select v-model="newCall.departmentId" class="select">
                <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
              </select>
            </div>
          </div>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="showCreateModal = false" class="btn-secondary">Cancel</button>
            <button type="submit" class="btn-primary">Create Call</button>
          </div>
        </form>
      </div>
    </div>

    <!-- Call Detail Modal -->
    <div v-if="showCallDetail && selectedCall" class="modal-overlay" @click.self="showCallDetail = false">
      <div class="modal-content max-w-2xl">
        <div class="flex items-start justify-between mb-4">
          <div>
            <h3 class="text-lg font-bold text-white">{{ selectedCall.type }}</h3>
            <p class="text-sm text-dark-400 font-mono">{{ selectedCall.callNumber }}</p>
          </div>
          <span
            class="text-xs font-bold px-2.5 py-1 rounded border"
            :class="priorityConfig[selectedCall.priority]?.class"
          >
            {{ priorityConfig[selectedCall.priority]?.label }}
          </span>
        </div>

        <div class="space-y-3 mb-4">
          <div><span class="text-dark-500 text-xs">Location:</span> <span class="text-dark-200 text-sm">{{ selectedCall.location }}</span></div>
          <div><span class="text-dark-500 text-xs">Status:</span> <span class="badge" :class="statusConfig[selectedCall.status]">{{ selectedCall.status.replace(/_/g, " ") }}</span></div>
          <div><span class="text-dark-500 text-xs">Description:</span> <p class="text-dark-300 text-sm mt-1">{{ selectedCall.description }}</p></div>
        </div>

        <!-- Status Actions -->
        <div v-if="authStore.hasPermission('dispatch')" class="flex gap-2 mb-4 flex-wrap">
          <button
            v-for="s in ['PENDING', 'ASSIGNED', 'EN_ROUTE', 'ON_SCENE', 'COMPLETED', 'CANCELLED']"
            :key="s"
            @click="updateCallStatus(selectedCall!.id, s)"
            class="btn-sm btn-ghost text-xs"
            :class="selectedCall.status === s ? 'ring-1 ring-primary-500' : ''"
          >
            {{ s.replace(/_/g, " ") }}
          </button>
        </div>

        <!-- Assigned Units -->
        <div class="mb-4">
          <h4 class="text-sm font-semibold text-dark-200 mb-2">Assigned Units</h4>
          <div class="space-y-1">
            <div
              v-for="a in selectedCall.assignments?.filter(x => !x.clearedAt)"
              :key="a.id"
              class="flex items-center justify-between bg-dark-700/50 rounded-lg px-3 py-2"
            >
              <span class="text-sm text-dark-200">
                {{ a.officer.callsign || `${a.officer.firstName} ${a.officer.lastName}` }}
              </span>
              <button
                v-if="authStore.hasPermission('dispatch')"
                @click="unassignOfficerFromCall(a.officer.id)"
                class="text-xs text-red-400 hover:text-red-300"
              >
                Remove
              </button>
            </div>
            <p v-if="!selectedCall.assignments?.filter(x => !x.clearedAt).length" class="text-xs text-dark-500">No units assigned</p>
          </div>

          <!-- Assign dropdown -->
          <div v-if="authStore.hasPermission('dispatch')" class="mt-2">
            <select
              class="select text-sm"
              @change="(e: any) => { assignOfficerToCall(e.target.value); e.target.value = ''; }"
            >
              <option value="">+ Assign Officer</option>
              <option
                v-for="o in officers.filter(o => !selectedCall?.assignments?.some(a => a.officer.id === o.id && !a.clearedAt))"
                :key="o.id"
                :value="o.id"
              >
                {{ o.callsign || o.badgeNumber }} — {{ o.firstName }} {{ o.lastName }}
              </option>
            </select>
          </div>
        </div>

        <!-- Notes -->
        <div>
          <h4 class="text-sm font-semibold text-dark-200 mb-2">Notes</h4>
          <div class="space-y-2 max-h-40 overflow-y-auto mb-2">
            <div
              v-for="note in selectedCall.notes"
              :key="note.id"
              class="bg-dark-700/50 rounded-lg px-3 py-2"
            >
              <p class="text-xs text-dark-300">{{ note.content }}</p>
              <p class="text-[10px] text-dark-500 mt-1">{{ note.createdBy }} • {{ new Date(note.createdAt).toLocaleString() }}</p>
            </div>
          </div>
          <div class="flex gap-2">
            <input
              v-model="newNote"
              class="input text-sm flex-1"
              placeholder="Add a note..."
              @keyup.enter="addNote"
            />
            <button @click="addNote" class="btn-sm btn-primary">Add</button>
          </div>
        </div>

        <div class="flex justify-end mt-4">
          <button @click="showCallDetail = false" class="btn-secondary">Close</button>
        </div>
      </div>
    </div>
  </div>
</template>
