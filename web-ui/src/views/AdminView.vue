<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";

const authStore = useAuthStore();

const tab = ref<"users" | "departments" | "ranks" | "logs" | "announcements">("users");
const data = ref<any[]>([]);
const loading = ref(false);
const showCreateUser = ref(false);
const showCreateDept = ref(false);
const showAssignDept = ref(false);
const selectedUser = ref<any>(null);
const showPromote = ref(false);
const departments = ref<any[]>([]);
const ranks = ref<any[]>([]);

const currentUserRankLevel = computed(() => authStore.user?.officer?.rank?.level ?? 0);
const availablePromoteRanks = computed(() => {
  if (!selectedUser.value?.officer) return [];
  const deptId = selectedUser.value.officer.departmentId;
  return ranks.value.filter((r: any) =>
    r.departmentId === deptId && r.level < currentUserRankLevel.value
  );
});
const availableDemoteRanks = computed(() => {
  if (!selectedUser.value?.officer) return [];
  const deptId = selectedUser.value.officer.departmentId;
  return ranks.value.filter((r: any) =>
    r.departmentId === deptId && r.level < (selectedUser.value.officer.rank?.level ?? 0)
  );
});

const tabs = [
  { key: "users", label: "Users", icon: "👤" },
  { key: "departments", label: "Departments", icon: "🏢" },
  { key: "ranks", label: "Ranks", icon: "🎖️" },
  { key: "logs", label: "Audit Logs", icon: "📜" },
  { key: "announcements", label: "Announcements", icon: "📢" },
];

const newUser = ref({
  username: "", password: "", email: "",
  firstName: "", lastName: "", badgeNumber: "",
  departmentId: "", rankId: "", callsign: "",
});
const formError = ref("");

const newDept = ref({ name: "", code: "", color: "" });

const assignForm = ref({ departmentId: "", rankId: "", callsign: "", badgeNumber: "" });
const promoteForm = ref({ rankId: "" });
const showCreateAnnouncement = ref(false);
const newAnnouncement = ref({ title: "", content: "", priority: "NORMAL", expiresAt: "" });

async function fetchData() {
  loading.value = true;
  try {
    const endpoints: Record<string, string> = {
      users: "/admin/users?limit=50",
      departments: "/admin/departments",
      ranks: "/admin/ranks",
      logs: "/admin/logs?limit=50",
      announcements: "/admin/announcements",
    };
    const { data: res } = await api.get(endpoints[tab.value]);
    data.value = res.data || res;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function fetchMeta() {
  try {
    const [deptRes, rankRes] = await Promise.all([
      api.get("/admin/departments"),
      api.get("/admin/ranks"),
    ]);
    departments.value = deptRes.data;
    ranks.value = rankRes.data;
  } catch { /* silent */ }
}

function switchTab(t: string) {
  tab.value = t as any;
  fetchData();
}

async function createUser() {
  formError.value = "";
  try {
    await api.post("/admin/users", newUser.value);
    showCreateUser.value = false;
    newUser.value = { username: "", password: "", email: "", firstName: "", lastName: "", badgeNumber: "", departmentId: "", rankId: "", callsign: "" };
    fetchData();
  } catch (err: any) {
    formError.value = err.response?.data?.error?.message || err.response?.data?.message || "Failed to create user. Please check the form and try again.";
  }
}

function openCreateUser() {
  formError.value = "";
  showCreateUser.value = true;
}

async function createDept() {
  formError.value = "";
  try {
    await api.post("/admin/departments", newDept.value);
    showCreateDept.value = false;
    newDept.value = { name: "", code: "", color: "" };
    fetchData();
    fetchMeta();
  } catch (err: any) {
    formError.value = err.response?.data?.error?.message || err.response?.data?.message || "Failed to create department.";
  }
}

function openCreateDept() {
  formError.value = "";
  showCreateDept.value = true;
}

function openCreateAnnouncement() {
  formError.value = "";
  newAnnouncement.value = { title: "", content: "", priority: "NORMAL", expiresAt: "" };
  showCreateAnnouncement.value = true;
}

async function createAnnouncement() {
  formError.value = "";
  try {
    const payload: any = {
      title: newAnnouncement.value.title,
      content: newAnnouncement.value.content,
      priority: newAnnouncement.value.priority,
    };
    if (newAnnouncement.value.expiresAt) {
      payload.expiresAt = new Date(newAnnouncement.value.expiresAt).toISOString();
    }
    await api.post("/admin/announcements", payload);
    showCreateAnnouncement.value = false;
    fetchData();
  } catch (err: any) {
    formError.value = err.response?.data?.error?.message || err.response?.data?.message || "Failed to create announcement.";
  }
}

async function deleteAnnouncement(id: string) {
  if (!confirm("Remove this announcement?")) return;
  try {
    await api.delete(`/admin/announcements/${id}`);
    fetchData();
  } catch { /* silent */ }
}

function openAssignDept(user: any) {
  formError.value = "";
  selectedUser.value = user;
  assignForm.value = {
    departmentId: user.officer?.department?.id || "",
    rankId: user.officer?.rank?.id || "",
    callsign: user.officer?.callsign || "",
    badgeNumber: user.officer?.badgeNumber || "",
  };
  showAssignDept.value = true;
}

async function assignDept() {
  if (!selectedUser.value) return;
  formError.value = "";
  try {
    await api.patch(`/admin/users/${selectedUser.value.id}/officer`, {
      firstName: selectedUser.value.officer?.firstName || selectedUser.value.username,
      lastName: selectedUser.value.officer?.lastName || "",
      ...assignForm.value,
    });
    showAssignDept.value = false;
    fetchData();
  } catch (err: any) {
    formError.value = err.response?.data?.error?.message || err.response?.data?.message || "Failed to assign department.";
  }
}

function openPromote(user: any) {
  formError.value = "";
  selectedUser.value = user;
  promoteForm.value = { rankId: "" };
  showPromote.value = true;
}

async function promoteUser(isPromote: boolean) {
  if (!selectedUser.value || !promoteForm.value.rankId) return;
  formError.value = "";
  try {
    const endpoint = isPromote ? "promote" : "demote";
    await api.post(`/admin/users/${selectedUser.value.id}/${endpoint}`, {
      rankId: promoteForm.value.rankId,
    });
    showPromote.value = false;
    fetchData();
  } catch (err: any) {
    formError.value = err.response?.data?.error?.message || `Failed to ${isPromote ? "promote" : "demote"} officer.`;
  }
}

async function toggleUserActive(user: any) {
  try {
    await api.patch(`/admin/users/${user.id}`, { active: !user.active });
    fetchData();
  } catch { /* silent */ }
}

async function resetPassword(userId: string) {
  const newPassword = prompt("Enter new password (min 8 chars):");
  if (!newPassword || newPassword.length < 8) return;
  try {
    await api.post(`/admin/users/${userId}/reset-password`, { newPassword });
    alert("Password reset successfully.");
  } catch { /* silent */ }
}

onMounted(() => { fetchData(); fetchMeta(); });
</script>

<template>
  <div class="p-6 space-y-6 max-w-[1400px] mx-auto">
    <!-- Premium Header -->
    <div class="flex items-start justify-between">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <div class="w-1 h-8 rounded-full gradient-accent"></div>
          <h2 class="text-2xl font-bold text-white tracking-tight">Administration</h2>
        </div>
        <p class="text-sm text-dark-400 ml-[1.1rem]">Manage users, departments, and system settings</p>
      </div>
      <div class="flex gap-2">
        <button v-if="tab === 'departments'" @click="openCreateDept" class="premium-btn-primary">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
          New Department
        </button>
        <button v-if="tab === 'users'" @click="openCreateUser" class="premium-btn-primary">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
          Create User
        </button>
        <button v-if="tab === 'announcements'" @click="openCreateAnnouncement" class="premium-btn-primary">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
          New Announcement
        </button>
      </div>
    </div>

    <!-- Premium Tab Bar -->
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

    <!-- Users Tab -->
    <div v-if="tab === 'users'" class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">User</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Officer</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Department</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Role</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Status</th>
            <th class="px-5 py-4 text-right text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="6" class="px-5 py-1"><div v-for="i in 5" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div></td></tr>
          <tr v-else-if="!data.length"><td colspan="6" class="px-5 py-16 text-center"><div class="text-5xl mb-4 opacity-40">👤</div><p class="text-dark-400 font-medium">No users found</p></td></tr>
          <tr v-for="u in data" :key="u.id" class="premium-table-row group">
            <td class="px-5 py-4">
              <div class="flex items-center gap-3">
                <div class="w-8 h-8 rounded-full bg-primary-500/20 flex items-center justify-center text-xs font-bold text-primary-300">
                  {{ u.username?.[0]?.toUpperCase() }}
                </div>
                <div>
                  <span class="text-dark-100 font-medium group-hover:text-white transition-colors">{{ u.username }}</span>
                  <p v-if="u.email" class="text-[11px] text-dark-500">{{ u.email }}</p>
                </div>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-300 text-xs">{{ u.officer ? `${u.officer.firstName} ${u.officer.lastName}` : '—' }}</span>
              <p v-if="u.officer?.badgeNumber" class="text-[11px] text-dark-500 font-mono">#{{ u.officer.badgeNumber }}</p>
            </td>
            <td class="px-5 py-4">
              <span v-if="u.officer?.department" class="premium-badge bg-primary-500/15 text-primary-300 ring-1 ring-primary-500/20">
                {{ u.officer.department.name }}
              </span>
              <span v-else class="text-dark-500 text-xs">Unassigned</span>
            </td>
            <td class="px-5 py-4">
              <div class="flex flex-wrap gap-1">
                <span v-for="p in u.permissions?.slice(0, 3)" :key="p.permission?.name" class="text-[10px] px-2 py-0.5 rounded-full bg-white/[0.04] text-dark-400">
                  {{ p.permission?.name }}
                </span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="premium-badge shadow-lg" :class="u.active ? 'bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/20 shadow-emerald-500/10' : 'bg-red-500/15 text-red-300 ring-1 ring-red-500/20 shadow-red-500/10'">
                <span class="w-1.5 h-1.5 rounded-full" :class="u.active ? 'bg-emerald-400' : 'bg-red-400'"></span>
                {{ u.active ? 'Active' : 'Inactive' }}
              </span>
            </td>
            <td class="px-5 py-4">
              <div class="flex items-center gap-1 justify-end">
                <button @click="openAssignDept(u)" class="px-2.5 py-1.5 rounded-lg text-xs text-primary-400 hover:bg-primary-500/10 transition-colors" title="Assign Department">
                  🏢
                </button>
                <button v-if="authStore.hasPermission('supervisor') || authStore.hasPermission('admin')" @click="openPromote(u)" class="px-2.5 py-1.5 rounded-lg text-xs text-emerald-400 hover:bg-emerald-500/10 transition-colors" title="Promote / Demote">
                  🎖️
                </button>
                <button @click="resetPassword(u.id)" class="px-2.5 py-1.5 rounded-lg text-xs text-amber-400 hover:bg-amber-500/10 transition-colors" title="Reset Password">
                  🔑
                </button>
                <button @click="toggleUserActive(u)" class="px-2.5 py-1.5 rounded-lg text-xs transition-colors" :class="u.active ? 'text-red-400 hover:bg-red-500/10' : 'text-emerald-400 hover:bg-emerald-500/10'" :title="u.active ? 'Deactivate' : 'Activate'">
                  {{ u.active ? '🚫' : '✅' }}
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Departments Tab -->
    <div v-if="tab === 'departments'" class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Department</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Code</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Officers</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="4" class="px-5 py-1"><div v-for="i in 3" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div></td></tr>
          <tr v-for="d in data" :key="d.id" class="premium-table-row group">
            <td class="px-5 py-4">
              <div class="flex items-center gap-3">
                <div class="w-8 h-8 rounded-lg flex items-center justify-center text-sm" :style="{ background: d.color ? d.color + '20' : 'rgba(59,130,246,0.15)' }">
                  🏢
                </div>
                <span class="text-dark-100 font-medium group-hover:text-white transition-colors">{{ d.name }}</span>
              </div>
            </td>
            <td class="px-5 py-4"><span class="font-mono text-xs text-dark-300 bg-white/[0.04] px-2.5 py-1 rounded-lg">{{ d.code }}</span></td>
            <td class="px-5 py-4"><span class="text-dark-400 text-xs">{{ d._count?.officers || 0 }}</span></td>
            <td class="px-5 py-4">
              <span class="premium-badge shadow-lg" :class="d.active ? 'bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/20 shadow-emerald-500/10' : 'bg-red-500/15 text-red-300 ring-1 ring-red-500/20'">
                {{ d.active ? 'Active' : 'Inactive' }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Ranks Tab -->
    <div v-if="tab === 'ranks'" class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Rank</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Department</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Level</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Badge Prefix</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="4" class="px-5 py-1"><div v-for="i in 3" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div></td></tr>
          <tr v-for="r in data" :key="r.id" class="premium-table-row group">
            <td class="px-5 py-4"><span class="text-dark-100 font-medium group-hover:text-white transition-colors">{{ r.name }}</span></td>
            <td class="px-5 py-4"><span class="text-dark-400 text-xs">{{ r.department?.name }}</span></td>
            <td class="px-5 py-4">
              <div class="flex items-center gap-2">
                <div class="w-16 h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
                  <div class="h-full rounded-full gradient-accent" :style="{ width: Math.min(r.level * 2, 100) + '%' }"></div>
                </div>
                <span class="text-xs text-dark-400">{{ r.level }}</span>
              </div>
            </td>
            <td class="px-5 py-4"><span class="font-mono text-xs text-dark-400">{{ r.badgePrefix || '—' }}</span></td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Audit Logs Tab -->
    <div v-if="tab === 'logs'" class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Time</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">User</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Action</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Resource</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="4" class="px-5 py-1"><div v-for="i in 5" :key="i" class="h-10 rounded-lg shimmer-loading mb-2"></div></td></tr>
          <tr v-for="l in data" :key="l.id" class="premium-table-row">
            <td class="px-5 py-3"><span class="text-dark-500 text-xs font-mono">{{ new Date(l.createdAt).toLocaleString() }}</span></td>
            <td class="px-5 py-3"><span class="text-dark-200 text-xs">{{ l.user?.username }}</span></td>
            <td class="px-5 py-3"><span class="premium-badge bg-sky-500/15 text-sky-300 ring-1 ring-sky-500/20">{{ l.action }}</span></td>
            <td class="px-5 py-3"><span class="text-dark-400 text-xs">{{ l.resource }}</span></td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Announcements Tab -->
    <div v-if="tab === 'announcements'" class="space-y-3">
      <div v-if="loading" class="glass-card p-8 text-center text-dark-500">Loading...</div>
      <div v-else-if="!data.length" class="glass-card p-12 text-center">
        <div class="text-5xl mb-4 opacity-40">📢</div>
        <p class="text-dark-400 font-medium">No announcements</p>
      </div>
      <div v-for="a in data" :key="a.id" class="glass-card-hover p-5">
        <div class="flex items-start justify-between mb-2">
          <div class="flex items-center gap-2">
            <span class="premium-badge" :class="{
              'bg-red-500/15 text-red-300 ring-1 ring-red-500/20': a.priority === 'URGENT',
              'bg-amber-500/15 text-amber-300 ring-1 ring-amber-500/20': a.priority === 'HIGH',
              'bg-blue-500/15 text-blue-300 ring-1 ring-blue-500/20': a.priority === 'NORMAL',
              'bg-slate-500/15 text-slate-300 ring-1 ring-slate-500/20': a.priority === 'LOW',
            }">{{ a.priority }}</span>
            <span class="text-sm font-semibold text-white">{{ a.title }}</span>
          </div>
          <button @click="deleteAnnouncement(a.id)" class="px-2 py-1.5 rounded-lg text-xs text-red-400 hover:bg-red-500/10 transition-colors" title="Remove">
            ✕
          </button>
        </div>
        <p class="text-sm text-dark-300 leading-relaxed">{{ a.content }}</p>
        <p class="text-[11px] text-dark-500 mt-3">By {{ a.createdBy }} • {{ new Date(a.createdAt).toLocaleString() }}</p>
      </div>
    </div>

    <!-- Create User Modal -->
    <div v-if="showCreateUser" class="premium-modal-overlay" @click.self="showCreateUser = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">Create User</h3>
            <p class="text-xs text-dark-400">Create a new account with optional officer profile</p>
          </div>
        </div>
        <form @submit.prevent="createUser" class="space-y-4">
          <div v-if="formError" class="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-300 text-sm">
            {{ formError }}
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Username</label>
              <input v-model="newUser.username" class="premium-input" required />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Password</label>
              <input v-model="newUser.password" type="password" class="premium-input" minlength="8" required />
            </div>
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Email (optional)</label>
            <input v-model="newUser.email" type="email" class="premium-input" />
          </div>
          <div class="border-t border-white/[0.06] pt-4">
            <p class="text-xs font-semibold text-primary-400 mb-3 uppercase tracking-wider">Officer Profile (optional)</p>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">First Name</label>
                <input v-model="newUser.firstName" class="premium-input" />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Last Name</label>
                <input v-model="newUser.lastName" class="premium-input" />
              </div>
            </div>
            <div class="grid grid-cols-3 gap-3 mt-3">
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Badge #</label>
                <input v-model="newUser.badgeNumber" class="premium-input" placeholder="e.g. 1234" />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Callsign</label>
                <input v-model="newUser.callsign" class="premium-input" placeholder="e.g. 1-ADAM-12" />
              </div>
              <div>
                <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Department</label>
                <select v-model="newUser.departmentId" class="premium-input">
                  <option value="">None</option>
                  <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
                </select>
              </div>
            </div>
            <div class="mt-3">
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Rank</label>
              <select v-model="newUser.rankId" class="premium-input">
                <option value="">None</option>
                <option v-for="r in ranks.filter(r => !newUser.departmentId || r.departmentId === newUser.departmentId)" :key="r.id" :value="r.id">{{ r.name }} (Lvl {{ r.level }})</option>
              </select>
            </div>
          </div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateUser = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Create User</button>
          </div>
        </form>
      </div>
    </div>

    <!-- Create Department Modal -->
    <div v-if="showCreateDept" class="premium-modal-overlay" @click.self="showCreateDept = false">
      <div class="premium-modal-content">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">🏢</div>
          <div>
            <h3 class="text-lg font-bold text-white">New Department</h3>
            <p class="text-xs text-dark-400">Add a new department to the system</p>
          </div>
        </div>
        <form @submit.prevent="createDept" class="space-y-4">
          <div v-if="formError" class="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-300 text-sm">
            {{ formError }}
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Name</label>
            <input v-model="newDept.name" class="premium-input" placeholder="e.g. Los Santos Police Department" required />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Code</label>
              <input v-model="newDept.code" class="premium-input uppercase font-mono" placeholder="e.g. LSPD" required />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Color</label>
              <input v-model="newDept.color" type="color" class="premium-input h-[42px] p-1 cursor-pointer" />
            </div>
          </div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateDept = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Create Department</button>
          </div>
        </form>
      </div>
    </div>

    <!-- Assign Department Modal -->
    <div v-if="showAssignDept && selectedUser" class="premium-modal-overlay" @click.self="showAssignDept = false">
      <div class="premium-modal-content">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">🏢</div>
          <div>
            <h3 class="text-lg font-bold text-white">Assign Department</h3>
            <p class="text-xs text-dark-400">{{ selectedUser.username }} — {{ selectedUser.officer?.firstName }} {{ selectedUser.officer?.lastName }}</p>
          </div>
        </div>
        <form @submit.prevent="assignDept" class="space-y-4">
          <div v-if="formError" class="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-300 text-sm">
            {{ formError }}
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Department</label>
            <select v-model="assignForm.departmentId" class="premium-input">
              <option value="">None</option>
              <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Rank</label>
            <select v-model="assignForm.rankId" class="premium-input">
              <option value="">None</option>
              <option v-for="r in ranks.filter(r => !assignForm.departmentId || r.departmentId === assignForm.departmentId)" :key="r.id" :value="r.id">{{ r.name }} (Lvl {{ r.level }})</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Badge #</label>
              <input v-model="assignForm.badgeNumber" class="premium-input" />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Callsign</label>
              <input v-model="assignForm.callsign" class="premium-input" />
            </div>
          </div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showAssignDept = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Save Assignment</button>
          </div>
        </form>
      </div>
    </div>

    <!-- Promote / Demote Modal -->
    <div v-if="showPromote && selectedUser" class="premium-modal-overlay" @click.self="showPromote = false">
      <div class="premium-modal-content">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">🎖️</div>
          <div>
            <h3 class="text-lg font-bold text-white">Promote / Demote</h3>
            <p class="text-xs text-dark-400">{{ selectedUser.officer?.firstName }} {{ selectedUser.officer?.lastName }} — Current: {{ selectedUser.officer?.rank?.name || 'Unassigned' }} (Level {{ selectedUser.officer?.rank?.level ?? 0 }})</p>
          </div>
        </div>
        <div v-if="formError" class="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-300 text-sm mb-4">
          {{ formError }}
        </div>
        <div class="space-y-4">
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">New Rank</label>
            <select v-model="promoteForm.rankId" class="premium-input">
              <option value="">Select a rank...</option>
              <optgroup label="⬆️ Promote To">
                <option v-for="r in availablePromoteRanks" :key="r.id" :value="r.id">{{ r.name }} (Lvl {{ r.level }})</option>
              </optgroup>
              <optgroup label="⬇️ Demote To">
                <option v-for="r in availableDemoteRanks" :key="r.id" :value="r.id">{{ r.name }} (Lvl {{ r.level }})</option>
              </optgroup>
            </select>
          </div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showPromote = false" class="premium-btn-secondary px-5">Cancel</button>
            <button v-if="promoteForm.rankId && ranks.find((r: any) => r.id === promoteForm.rankId)?.level > (selectedUser.officer?.rank?.level ?? 0)"
              @click="promoteUser(true)" class="premium-btn-primary px-6">⬆️ Promote</button>
            <button v-else-if="promoteForm.rankId"
              @click="promoteUser(false)" class="px-6 py-2.5 rounded-xl text-sm font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/30 hover:bg-amber-500/30 transition-colors">⬇️ Demote</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Create Announcement Modal -->
    <div v-if="showCreateAnnouncement" class="premium-modal-overlay" @click.self="showCreateAnnouncement = false">
      <div class="premium-modal-content max-w-xl">
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">📢</div>
          <div>
            <h3 class="text-lg font-bold text-white">New Announcement</h3>
            <p class="text-xs text-dark-400">Broadcast a message to all officers (also sends as a notification)</p>
          </div>
        </div>
        <form @submit.prevent="createAnnouncement" class="space-y-4">
          <div v-if="formError" class="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-300 text-sm">
            {{ formError }}
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Title</label>
            <input v-model="newAnnouncement.title" class="premium-input" placeholder="e.g. Server Maintenance Tonight" required />
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Content</label>
            <textarea v-model="newAnnouncement.content" class="premium-input" rows="4" placeholder="Write your announcement..." required></textarea>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Priority</label>
              <select v-model="newAnnouncement.priority" class="premium-input">
                <option value="LOW">🟢 Low</option>
                <option value="NORMAL">🔵 Normal</option>
                <option value="HIGH">🟠 High</option>
                <option value="URGENT">🔴 Urgent</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Expires (optional)</label>
              <input v-model="newAnnouncement.expiresAt" type="datetime-local" class="premium-input" />
            </div>
          </div>
          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateAnnouncement = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">📢 Publish Announcement</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
