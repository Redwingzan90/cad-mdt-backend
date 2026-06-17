<script setup lang="ts">
import { ref, onMounted, watch } from "vue";
import { useRouter, useRoute } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { useNotificationStore } from "@/stores/notifications";
import { isConnected } from "@/api/socket";
import ToastNotification from "@/components/ToastNotification.vue";
import api from "@/api/client";

const router = useRouter();
const route = useRoute();
const authStore = useAuthStore();
const notifStore = useNotificationStore();

const visible = ref(false);
const sidebarOpen = ref(true);
const showProfile = ref(false);
const showDMVRegistration = ref(false);
const showCivilianRegistration = ref(false);
const showGunLicense = ref(false);
const showInsurance = ref(false);
const gunLicenseData = ref<any>({});
const insuranceData = ref<any>({});
const gunLicenseCharacters = ref<any[]>([]);
const insuranceCharacters = ref<any[]>([]);
const insuranceVehicles = ref<any[]>([]);
const gunLicenseSelectedCharId = ref('');
const insuranceSelectedCharId = ref('');
const insuranceSelectedPlate = ref('');
const isOnDuty = ref(false);
const dutyLoading = ref(false);
const dmvData = ref<any>({});
const civilianRegData = ref<any>({});

const navItems = [
  { name: "Dashboard", path: "/dashboard", icon: "📊", permission: null },
  { name: "Dispatch", path: "/dispatch", icon: "🚨", permission: "dispatch" },
  { name: "Officers", path: "/officers", icon: "👮", permission: null },
  { name: "Civilians", path: "/civilians", icon: "👥", permission: null },
  { name: "Vehicles", path: "/vehicles", icon: "🚗", permission: null },
  { name: "Criminal", path: "/criminal", icon: "📋", permission: null },
  { name: "Reports", path: "/reports", icon: "📝", permission: null },
  { name: "BOLOs", path: "/bolos", icon: "⚠️", permission: null },
  { name: "Evidence", path: "/evidence", icon: "🔍", permission: null },
  { name: "Admin", path: "/admin", icon: "⚙️", permission: "admin", altPermissions: ["supervisor", "manage_officers"] },
];

const filteredNav = ref(navItems);

watch(
  () => authStore.user,
  () => {
    filteredNav.value = navItems.filter((item) => {
      if (!item.permission) return true;
      if (authStore.hasPermission(item.permission)) return true;
      // Check alt permissions (e.g. supervisors can see Admin tab)
      if ((item as any).altPermissions) {
        return authStore.hasAnyPermission(...(item as any).altPermissions);
      }
      return false;
    });
  },
  { immediate: true }
);

function toggleSidebar() {
  sidebarOpen.value = !sidebarOpen.value;
}

function navigateTo(path: string) {
  router.push(path);
}

// DMV Registration
async function toggleDuty() {
  const officer = authStore.user?.officer;
  if (!officer) return;
  dutyLoading.value = true;
  try {
    if (isOnDuty.value) {
      await api.post(`/officers/${officer.id}/go-off-duty`);
      isOnDuty.value = false;
    } else {
      const departmentId = officer.department?.id;
      if (!departmentId) {
        alert('No department assigned. Contact an admin.');
        dutyLoading.value = false;
        return;
      }
      await api.post(`/officers/${officer.id}/go-on-duty`, {
        callsign: officer.callsign || officer.badgeNumber || '0-0-0',
        departmentId,
      });
      isOnDuty.value = true;
    }
  } catch (err: any) {
    const msg = err?.response?.data?.error || err?.message || 'Failed to toggle duty.';
    alert(msg);
  } finally {
    dutyLoading.value = false;
  }
}

// Initialize duty state from officer status
onMounted(() => {
  if (authStore.isAuthenticated) {
    notifStore.initSocketListeners();
    notifStore.fetchUnreadCount();
    if (authStore.user?.officer) {
      isOnDuty.value = authStore.user.officer.status !== 'OFF_DUTY';
    }
  }
});

const dmvForm = ref({ plate: '', model: '', color: '', year: '' });
const dmvCharacters = ref<any[]>([]);
const dmvSelectedCharId = ref('');

function submitDMVRegistration() {
  const body: any = { ...dmvForm.value };
  if (dmvSelectedCharId.value) {
    body.civilianId = dmvSelectedCharId.value;
  }
  fetch('https://cad-mdt/submitVehicleRegistration', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => {});
  showDMVRegistration.value = false;
  dmvForm.value = { plate: '', model: '', color: '', year: '' };
  dmvSelectedCharId.value = '';
}

// Civilian Registration (Multi-Character)
const civForm = ref({ firstName: '', lastName: '', dateOfBirth: '', gender: '', address: '', phone: '' });
const civCharacters = ref<any[]>([]);
const civShowNewForm = ref(false);

function submitCivilianRegistration() {
  fetch('https://cad-mdt/submitCivilianRegistration', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(civForm.value),
  }).catch(() => {});
  showCivilianRegistration.value = false;
  civForm.value = { firstName: '', lastName: '', dateOfBirth: '', gender: '', address: '', phone: '' };
  civShowNewForm.value = false;
}

function selectCharacter(civilianId: string) {
  fetch('https://cad-mdt/selectCharacter', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ civilianId }),
  }).catch(() => {});
  showCivilianRegistration.value = false;
}



function cancelNPCInteraction() {
  showDMVRegistration.value = false;
  showCivilianRegistration.value = false;
  showGunLicense.value = false;
  showInsurance.value = false;
  dmvData.value = {};
  civilianRegData.value = {};
  gunLicenseData.value = {};
  insuranceData.value = {};
  // Release NUI focus so cursor is freed
  fetch('https://cad-mdt/cancelNPCInteraction', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  }).catch(() => {});
}

// Safety: auto-close any NPC modal after 30s if still open (prevents stuck cursor)
let npcSafetyTimer: any = null;
watch([showDMVRegistration, showCivilianRegistration, showGunLicense, showInsurance], ([dmv, civ, gun, ins]) => {
  clearTimeout(npcSafetyTimer);
  if (dmv || civ || gun || ins) {
    npcSafetyTimer = setTimeout(() => {
      if (showDMVRegistration.value || showCivilianRegistration.value || showGunLicense.value || showInsurance.value) {
        cancelNPCInteraction();
      }
    }, 30000);
  }
});

// Watch for DMV data to pre-fill form
watch(dmvData, (val) => {
  if (val && val.plate !== undefined) {
    dmvForm.value = {
      plate: val.plate || '',
      model: val.model || '',
      color: val.color || '',
      year: val.year || '',
    };
  }
});

// Watch for civilian reg data to pre-fill form + load characters
watch(civilianRegData, (val) => {
  if (val && val.firstName !== undefined) {
    civForm.value = {
      firstName: val.firstName || '',
      lastName: val.lastName || '',
      dateOfBirth: '',
      gender: '',
      address: '',
      phone: '',
    };
  }
  // Load existing characters from the NUI data
  if (val && val.characters) {
    civCharacters.value = val.characters;
  } else {
    civCharacters.value = [];
  }
  // Default to showing character list if they have characters, otherwise show new form
  civShowNewForm.value = !(val && val.characters && val.characters.length > 0);
});

function submitGunLicense() {
  const body: any = {};
  if (gunLicenseSelectedCharId.value) {
    body.civilianId = gunLicenseSelectedCharId.value;
  }
  fetch('https://cad-mdt/submitGunLicense', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => {});
  showGunLicense.value = false;
  gunLicenseSelectedCharId.value = '';
}

function submitInsurance() {
  if (!insuranceSelectedPlate.value) return;
  const body: any = {
    plate: insuranceSelectedPlate.value,
  };
  if (insuranceSelectedCharId.value) {
    body.civilianId = insuranceSelectedCharId.value;
  }
  fetch('https://cad-mdt/submitInsurance', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => {});
  showInsurance.value = false;
  insuranceSelectedPlate.value = '';
  insuranceSelectedCharId.value = '';
}

async function handleLogout() {
  await authStore.logout();
  router.push("/login");
}

// Handle NUI messages from FiveM
window.addEventListener("message", (event) => {
  const data = event.data;
  if (data.action === "open") {
    visible.value = true;
  } else if (data.action === "close") {
    visible.value = false;
  } else if (data.action === "plateResult" && data.data) {
    // Navigate to vehicles page and store plate result for display
    visible.value = true;
    router.push("/vehicles").then(() => {
      // Give Vue time to render, then dispatch a custom event
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent("cad:plateResult", { detail: data.data }));
      }, 100);
    });
  } else if (data.action === "newDispatchCall" || data.action === "updateDispatchCall") {
    visible.value = true;
  } else if (data.action === "openDMVRegistration") {
    // Don't show the full MDT - only show the standalone NPC modal
    showDMVRegistration.value = true;
    dmvData.value = data;
    // Load characters for the DMV owner selector
    dmvCharacters.value = data.characters || [];
    dmvSelectedCharId.value = '';
    // Auto-select active character
    if (data.characters && data.characters.length > 0) {
      const active = data.characters.find((c: any) => c.isActive);
      if (active) dmvSelectedCharId.value = active.id;
    }
  } else if (data.action === "openCivilianRegistration") {
    // Don't show the full MDT - only show the standalone NPC modal
    showCivilianRegistration.value = true;
    civilianRegData.value = data;
  } else if (data.action === "openGunLicense") {
    showGunLicense.value = true;
    gunLicenseData.value = data;
    gunLicenseCharacters.value = data.characters || [];
    gunLicenseSelectedCharId.value = '';
    if (data.characters && data.characters.length > 0) {
      const active = data.characters.find((c: any) => c.isActive);
      if (active) gunLicenseSelectedCharId.value = active.id;
    }
  } else if (data.action === "openInsurance") {
    showInsurance.value = true;
    insuranceData.value = data;
    insuranceCharacters.value = data.characters || [];
    insuranceVehicles.value = data.vehicles || [];
    insuranceSelectedCharId.value = '';
    insuranceSelectedPlate.value = '';
    if (data.characters && data.characters.length > 0) {
      const active = data.characters.find((c: any) => c.isActive);
      if (active) insuranceSelectedCharId.value = active.id;
    }
  }
});

// Close on ESC (standard FiveM pattern)
window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    // If NPC forms are open, close them first
    if (showDMVRegistration.value || showCivilianRegistration.value || showGunLicense.value || showInsurance.value) {
      cancelNPCInteraction();
      return;
    }
    if (visible.value) {
      visible.value = false;
      // Notify FiveM to release NUI focus
      fetch("https://cad-mdt/close", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      }).catch(() => {});
    }
  }
});


</script>

<template>
  <!-- Tablet wrapper with bezel frame -->
  <div v-show="visible" class="tablet-wrapper" :class="{ 'tablet-open': visible }">
    <div class="tablet-bezel">
      <div class="tablet-notch"></div>
      <div class="tablet-screen flex overflow-hidden bg-dark-950">
    <!-- Sidebar -->
    <aside
      v-if="authStore.isAuthenticated"
      class="flex flex-col bg-dark-900 border-r border-dark-700 transition-all duration-300"
      :class="sidebarOpen ? 'w-56' : 'w-16'"
    >
      <!-- Logo / Header -->
      <div class="flex items-center h-14 px-4 border-b border-dark-700">
        <div class="flex items-center gap-3 overflow-hidden">
          <span class="text-2xl flex-shrink-0">🛡️</span>
          <transition name="fade">
            <div v-if="sidebarOpen" class="flex flex-col min-w-0">
              <span class="text-sm font-bold text-white truncate">CAD/MDT</span>
              <span class="text-xs text-dark-400 truncate">Police System</span>
            </div>
          </transition>
        </div>
      </div>

      <!-- Navigation -->
      <nav class="flex-1 py-3 overflow-y-auto">
        <button
          v-for="item in filteredNav"
          :key="item.path"
          @click="navigateTo(item.path)"
          class="flex items-center w-full px-4 py-2.5 text-sm transition-colors duration-150 group"
          :class="
            route.path === item.path
              ? 'bg-primary-600/20 text-primary-400 border-r-2 border-primary-500'
              : 'text-dark-300 hover:bg-dark-800 hover:text-dark-100'
          "
        >
          <span class="text-lg flex-shrink-0 w-6 text-center">{{ item.icon }}</span>
          <transition name="fade">
            <span v-if="sidebarOpen" class="ml-3 truncate">{{ item.name }}</span>
          </transition>
        </button>
      </nav>

      <!-- User Info / Footer -->
      <div class="border-t border-dark-700 p-3">
        <!-- Connection status -->
        <div class="flex items-center gap-2 mb-2" :class="sidebarOpen ? 'px-1' : 'justify-center'">
          <span
            class="w-2 h-2 rounded-full flex-shrink-0"
            :class="isConnected ? 'bg-green-500' : 'bg-red-500 animate-pulse'"
          />
          <span v-if="sidebarOpen" class="text-xs text-dark-400">
            {{ isConnected ? "Connected" : "Disconnected" }}
          </span>
        </div>

        <!-- Profile button -->
        <button
          @click="showProfile = !showProfile"
          class="flex items-center w-full p-2 rounded-lg hover:bg-dark-800 transition-colors"
        >
          <div
            class="w-8 h-8 rounded-full bg-primary-600 flex items-center justify-center text-white text-sm font-bold flex-shrink-0"
          >
            {{ authStore.user?.officer?.firstName?.[0] || authStore.user?.username?.[0]?.toUpperCase() || "?" }}
          </div>
          <transition name="fade">
            <div v-if="sidebarOpen" class="ml-3 text-left min-w-0">
              <div class="text-sm font-medium text-dark-100 truncate">
                {{ authStore.user?.officer
                  ? `${authStore.user.officer.firstName} ${authStore.user.officer.lastName}`
                  : authStore.user?.username }}
              </div>
              <div class="text-xs text-dark-400 truncate">
                {{ authStore.user?.officer?.callsign || authStore.user?.officer?.badgeNumber || "No Badge" }}
                <span v-if="authStore.user?.officer?.department" class="text-primary-400">
                  • {{ authStore.user.officer.department.code || authStore.user.officer.department.name }}
                </span>
              </div>
            </div>
          </transition>
        </button>

        <!-- Logout -->
        <button
          v-if="sidebarOpen"
          @click="handleLogout"
          class="flex items-center w-full mt-1 px-2 py-1.5 text-xs text-dark-400 hover:text-red-400 transition-colors"
        >
          <span>🚪</span>
          <span class="ml-2">Sign Out</span>
        </button>
      </div>
    </aside>

    <!-- Main Content -->
    <main class="flex-1 flex flex-col overflow-hidden">
      <!-- Top Bar -->
      <header
        v-if="authStore.isAuthenticated"
        class="flex items-center justify-between h-12 px-4 bg-dark-900 border-b border-dark-700"
      >
        <div class="flex items-center gap-3">
          <button @click="toggleSidebar" class="text-dark-400 hover:text-dark-200 transition-colors">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
          <h1 class="text-sm font-semibold text-dark-200">
            {{ route.name }}
          </h1>
        </div>

        <div class="flex items-center gap-3">
          <!-- Notification bell -->
          <button
            @click="router.push('/dashboard')"
            class="relative p-1.5 text-dark-400 hover:text-dark-200 transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
            </svg>
            <span
              v-if="notifStore.unreadCount > 0"
              class="absolute -top-0.5 -right-0.5 w-4 h-4 bg-red-500 text-white text-[10px] rounded-full flex items-center justify-center font-bold"
            >
              {{ notifStore.unreadCount > 9 ? "9+" : notifStore.unreadCount }}
            </span>
          </button>

          <!-- Duty Toggle (officers only) -->
          <button
            v-if="authStore.user?.officer"
            @click="toggleDuty"
            :disabled="dutyLoading"
            class="flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-semibold transition-all duration-200 border"
            :class="isOnDuty
              ? 'bg-green-500/15 text-green-300 border-green-500/30 hover:bg-green-500/25'
              : 'bg-dark-700/50 text-dark-400 border-white/[0.06] hover:bg-dark-600/50 hover:text-dark-200'"
          >
            <span class="w-2 h-2 rounded-full" :class="isOnDuty ? 'bg-green-400 animate-pulse' : 'bg-dark-500'"></span>
            {{ dutyLoading ? '...' : (isOnDuty ? 'On Duty' : 'Off Duty') }}
          </button>

          <!-- Current time -->
          <span class="text-xs text-dark-400 font-mono tabular-nums" id="clock"></span>
        </div>
      </header>

      <!-- Page Content -->
      <div class="flex-1 overflow-auto">
        <router-view v-slot="{ Component }">
          <transition name="page" mode="out-in">
            <component :is="Component" />
          </transition>
        </router-view>
      </div>
    </main>

      </div>  </div>

    <!-- Toast Notifications (outside bezel, inside visibility guard) -->
    <div class="absolute top-4 right-4 z-50 flex flex-col gap-2 max-w-sm pointer-events-auto">
      <ToastNotification
        v-for="toast in notifStore.toasts"
        :key="toast.id"
        :notification="toast"
        @close="notifStore.removeToast(toast.id)"
      />
    </div>
  </div>

  <!-- DMV Vehicle Registration Modal (standalone - outside tablet wrapper) -->
  <div v-if="showDMVRegistration" class="npc-modal-overlay" @click.self="cancelNPCInteraction">
    <div class="npc-modal">
      <div class="npc-modal-header">
        <div class="npc-modal-icon">🚗</div>
        <div>\n          <h3 class="text-lg font-bold text-white">Vehicle Registration</h3>
          <p class="text-xs text-dark-400">{{ dmvData.location || 'DMV Office' }}</p>
        </div>
      </div>
      <form @submit.prevent="submitDMVRegistration" class="npc-modal-body">
        <!-- Character selector (if player has multiple characters) -->
        <div v-if="dmvCharacters.length > 1" class="npc-field">
          <label class="npc-label">Register Under Character</label>
          <select v-model="dmvSelectedCharId" class="npc-input">
            <option v-for="c in dmvCharacters" :key="c.id" :value="c.id">
              {{ c.firstName }} {{ c.lastName }} {{ c.isActive ? '(Active)' : '' }}
            </option>
          </select>
        </div>
        <div v-else-if="dmvCharacters.length === 1" class="text-xs text-sky-400 bg-sky-500/10 rounded-lg px-3 py-2">
          🚗 Registering under: <strong>{{ dmvCharacters[0].firstName }} {{ dmvCharacters[0].lastName }}</strong>
        </div>
        <div class="npc-field">
          <label class="npc-label">License Plate</label>
          <input v-model="dmvForm.plate" class="npc-input" placeholder="e.g. ABC1234" maxlength="8" required />
        </div>
        <div class="npc-field">
          <label class="npc-label">Vehicle Model</label>
          <input v-model="dmvForm.model" class="npc-input" placeholder="e.g. Dominator" required />
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div class="npc-field">
            <label class="npc-label">Color</label>
            <input v-model="dmvForm.color" class="npc-input" placeholder="e.g. Red" />
          </div>
          <div class="npc-field">
            <label class="npc-label">Year</label>
            <input v-model="dmvForm.year" class="npc-input" placeholder="e.g. 2024" />
          </div>
        </div>
        <div v-if="dmvData.cost > 0" class="text-xs text-amber-400 bg-amber-500/10 rounded-lg px-3 py-2">
          Registration Cost: ${{ dmvData.cost }}
        </div>
        <div v-if="dmvCharacters.length === 0" class="text-xs text-red-400 bg-red-500/10 rounded-lg px-3 py-2">
          ⚠️ You must register a civilian ID first. Visit City Hall.
        </div>
        <div class="npc-modal-actions">
          <button type="button" @click="cancelNPCInteraction" class="npc-btn npc-btn-cancel">Cancel</button>
          <button type="submit" class="npc-btn npc-btn-primary" :disabled="dmvCharacters.length === 0">Register Vehicle</button>
        </div>
      </form>
    </div>
  </div>

  <!-- Civilian Registration Modal (Multi-Character - standalone) -->
  <div v-if="showCivilianRegistration" class="npc-modal-overlay" @click.self="cancelNPCInteraction">
    <div class="npc-modal" :style="civCharacters.length > 0 ? 'width: 480px' : ''">
      <div class="npc-modal-header">
        <div class="npc-modal-icon">🪪</div>
        <div>
          <h3 class="text-lg font-bold text-white">City Hall — ID Office</h3>
          <p class="text-xs text-dark-400">{{ civilianRegData.location || 'City Hall' }}</p>
        </div>
      </div>
      <div class="npc-modal-body">
        <!-- Existing Characters List -->
        <div v-if="civCharacters.length > 0 && !civShowNewForm">
          <label class="npc-label mb-2 block">Your Characters</label>
          <div class="space-y-2 max-h-[240px] overflow-y-auto">
            <div
              v-for="c in civCharacters"
              :key="c.id"
              class="rounded-xl px-3 py-3 border transition-all cursor-pointer"
              :class="c.isActive
                ? 'bg-primary-500/15 border-primary-500/30'
                : 'bg-dark-700/40 border-white/5 hover:border-white/15 hover:bg-dark-700/60'"
              @click="selectCharacter(c.id)"
            >
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-semibold text-white">{{ c.firstName }} {{ c.lastName }}</p>
                  <p class="text-[11px] text-dark-400">
                    {{ c.gender ? c.gender + ' • ' : '' }}
                    DOB: {{ new Date(c.dateOfBirth).toLocaleDateString() }}
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <span v-if="c.isActive" class="text-[10px] font-bold uppercase tracking-wider text-primary-400 bg-primary-500/20 px-2 py-0.5 rounded-full">Active</span>
                  <span v-if="c.vehicles && c.vehicles.length > 0" class="text-[10px] text-dark-400 bg-dark-600/50 px-1.5 py-0.5 rounded-full">🚗 {{ c.vehicles.length }}</span>
                </div>
              </div>
              <div v-if="c.licenses && c.licenses.length > 0" class="mt-1.5 flex gap-1.5 flex-wrap">
                <span v-for="l in c.licenses" :key="l.number" class="text-[10px]" :class="l.status === 'VALID' ? 'text-emerald-400' : 'text-red-400'">
                  {{ l.type }}: {{ l.number }}
                </span>
              </div>
            </div>
          </div>
          <button
            type="button"
            @click="civShowNewForm = true"
            class="mt-3 w-full npc-btn npc-btn-secondary text-center"
          >
            + Create New Character
          </button>
        </div>

        <!-- New Character Form -->
        <form v-if="civShowNewForm || civCharacters.length === 0" @submit.prevent="submitCivilianRegistration">
          <div v-if="civCharacters.length > 0" class="mb-3">
            <button type="button" @click="civShowNewForm = false" class="text-xs text-primary-400 hover:text-primary-300">
              ← Back to Characters
            </button>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="npc-field">
              <label class="npc-label">First Name</label>
              <input v-model="civForm.firstName" class="npc-input" placeholder="First name" required />
            </div>
            <div class="npc-field">
              <label class="npc-label">Last Name</label>
              <input v-model="civForm.lastName" class="npc-input" placeholder="Last name" required />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="npc-field">
              <label class="npc-label">Date of Birth</label>
              <input v-model="civForm.dateOfBirth" type="date" class="npc-input" required />
            </div>
            <div class="npc-field">
              <label class="npc-label">Gender</label>
              <select v-model="civForm.gender" class="npc-input">
                <option value="">Select...</option>
                <option value="Male">Male</option>
                <option value="Female">Female</option>
                <option value="Other">Other</option>
              </select>
            </div>
          </div>
          <div class="npc-field">
            <label class="npc-label">Address</label>
            <input v-model="civForm.address" class="npc-input" placeholder="e.g. 123 Vinewood Blvd" />
          </div>
          <div class="npc-field">
            <label class="npc-label">Phone Number</label>
            <input v-model="civForm.phone" class="npc-input" placeholder="e.g. 555-0123" />
          </div>
          <div class="text-xs text-emerald-400 bg-emerald-500/10 rounded-lg px-3 py-2">
            📋 A driver's license will be issued upon registration. This character will become your active one and appear in the Civilian Database.
          </div>
          <div class="npc-modal-actions">
            <button type="button" @click="cancelNPCInteraction" class="npc-btn npc-btn-cancel">Cancel</button>
            <button type="submit" class="npc-btn npc-btn-primary">Register Civilian ID</button>
          </div>
        </form>

        <!-- Close button for character list view -->
        <div v-if="civCharacters.length > 0 && !civShowNewForm" class="npc-modal-actions mt-2">
          <button type="button" @click="cancelNPCInteraction" class="npc-btn npc-btn-cancel">Close</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Gun License Modal (standalone) -->
  <div v-if="showGunLicense" class="npc-modal-overlay" @click.self="cancelNPCInteraction">
    <div class="npc-modal">
      <div class="npc-modal-header">
        <div class="npc-modal-icon">🛡️</div>
        <div>
          <h3 class="text-lg font-bold text-white">Gun License Clerk</h3>
          <p class="text-xs text-dark-400">{{ gunLicenseData.location || 'Gun Store' }}</p>
        </div>
      </div>
      <div class="npc-modal-body">
        <div v-if="gunLicenseCharacters.length > 1">
          <label class="npc-label mb-2 block">Apply As Character</label>
          <select v-model="gunLicenseSelectedCharId" class="npc-input">
            <option v-for="c in gunLicenseCharacters" :key="c.id" :value="c.id">
              {{ c.firstName }} {{ c.lastName }} {{ c.isActive ? '(Active)' : '' }}
            </option>
          </select>
        </div>
        <div v-else-if="gunLicenseCharacters.length === 1" class="text-xs text-sky-400 bg-sky-500/10 rounded-lg px-3 py-2">
          🛡️ Applying as: <strong>{{ gunLicenseCharacters[0].firstName }} {{ gunLicenseCharacters[0].lastName }}</strong>
        </div>
        <div class="text-xs text-dark-400 bg-dark-700/50 rounded-lg px-3 py-2">
          📋 Requirements: A valid driver's license is required before applying for a gun license. You must be a registered civilian.
        </div>
        <div v-if="gunLicenseCharacters.length === 0" class="text-xs text-red-400 bg-red-500/10 rounded-lg px-3 py-2">
          ⚠️ You must register as a civilian first. Visit City Hall.
        </div>
        <div class="npc-modal-actions">
          <button type="button" @click="cancelNPCInteraction" class="npc-btn npc-btn-cancel">Cancel</button>
          <button type="button" @click="submitGunLicense" class="npc-btn npc-btn-primary" :disabled="gunLicenseCharacters.length === 0">Apply for Gun License</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Insurance Modal (standalone) -->
  <div v-if="showInsurance" class="npc-modal-overlay" @click.self="cancelNPCInteraction">
    <div class="npc-modal">
      <div class="npc-modal-header">
        <div class="npc-modal-icon">🚗</div>
        <div>
          <h3 class="text-lg font-bold text-white">Insurance Agent</h3>
          <p class="text-xs text-dark-400">{{ insuranceData.location || 'Insurance Office' }}</p>
        </div>
      </div>
      <div class="npc-modal-body">
        <div v-if="insuranceCharacters.length > 1">
          <label class="npc-label mb-2 block">Insure As Character</label>
          <select v-model="insuranceSelectedCharId" class="npc-input">
            <option v-for="c in insuranceCharacters" :key="c.id" :value="c.id">
              {{ c.firstName }} {{ c.lastName }} {{ c.isActive ? '(Active)' : '' }}
            </option>
          </select>
        </div>
        <div v-if="insuranceVehicles.length > 0">
          <label class="npc-label mb-2 block">Select Vehicle</label>
          <select v-model="insuranceSelectedPlate" class="npc-input">
            <option value="">Choose a vehicle...</option>
            <option v-for="v in insuranceVehicles" :key="v.plate" :value="v.plate">
              {{ v.plate }} — {{ v.color }} {{ v.model }}
            </option>
          </select>
        </div>
        <div v-else class="text-xs text-amber-400 bg-amber-500/10 rounded-lg px-3 py-2">
          ⚠️ No registered vehicles found. Register a vehicle at the DMV first.
        </div>
        <div v-if="insuranceCharacters.length === 0" class="text-xs text-red-400 bg-red-500/10 rounded-lg px-3 py-2">
          ⚠️ You must register as a civilian first. Visit City Hall.
        </div>
        <div class="npc-modal-actions">
          <button type="button" @click="cancelNPCInteraction" class="npc-btn npc-btn-cancel">Cancel</button>
          <button type="button" @click="submitInsurance" class="npc-btn npc-btn-primary" :disabled="!insuranceSelectedPlate || insuranceCharacters.length === 0">Get Insurance</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ============================================================
   Tablet Bezel Frame
   ============================================================ */
.tablet-wrapper {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
  pointer-events: none;
}

.tablet-bezel {
  position: relative;
  width: 90vw;
  height: 88vh;
  max-width: 1400px;
  max-height: 900px;
  background: linear-gradient(145deg, #1a1a2e 0%, #0d0d1a 50%, #16162a 100%);
  border-radius: 24px;
  padding: 12px;
  box-shadow:
    0 0 0 2px rgba(255, 255, 255, 0.05),
    0 0 0 4px rgba(0, 0, 0, 0.4),
    0 25px 80px rgba(0, 0, 0, 0.6),
    0 10px 30px rgba(0, 0, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.06);
  pointer-events: auto;
  transition: transform 0.35s cubic-bezier(0.16, 1, 0.3, 1),
              opacity 0.3s ease;
}

/* Tablet open/close animation */
.tablet-open .tablet-bezel {
  animation: tabletOpen 0.4s cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

@keyframes tabletOpen {
  0% {
    opacity: 0;
    transform: scale(0.85) translateY(30px);
  }
  100% {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}

/* Camera notch at top */
.tablet-notch {
  position: absolute;
  top: 3px;
  left: 50%;
  transform: translateX(-50%);
  width: 80px;
  height: 6px;
  background: linear-gradient(90deg, #0a0a15, #1a1a30, #0a0a15);
  border-radius: 0 0 10px 10px;
  z-index: 10;
}
.tablet-notch::after {
  content: '';
  position: absolute;
  top: 1px;
  left: 50%;
  transform: translateX(-50%);
  width: 6px;
  height: 6px;
  background: #1e3a5f;
  border-radius: 50%;
  box-shadow: 0 0 4px rgba(59, 130, 246, 0.3);
}

/* Inner screen with slight inset and rounded corners */
.tablet-screen {
  width: 100%;
  height: 100%;
  border-radius: 14px;
  overflow: hidden;
  box-shadow:
    inset 0 0 0 1px rgba(255, 255, 255, 0.03),
    inset 0 2px 8px rgba(0, 0, 0, 0.3);
}

/* ============================================================
   Page Transitions
   ============================================================ */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

.page-enter-active {
  transition: opacity 0.15s ease, transform 0.15s ease;
}
.page-leave-active {
  transition: opacity 0.1s ease;
}
.page-enter-from {
  opacity: 0;
  transform: translateY(4px);
}
.page-leave-to {
  opacity: 0;
}

/* ============================================================
   NPC Registration Modals (standalone overlay)
   ============================================================ */
.npc-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 200;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  pointer-events: auto;
}

.npc-modal {
  width: 420px;
  max-width: 90vw;
  background: linear-gradient(145deg, #1e293b 0%, #0f172a 100%);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 16px;
  box-shadow:
    0 25px 60px rgba(0, 0, 0, 0.5),
    0 0 0 1px rgba(255, 255, 255, 0.05);
  animation: npcModalIn 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

@keyframes npcModalIn {
  0% { opacity: 0; transform: scale(0.92) translateY(20px); }
  100% { opacity: 1; transform: scale(1) translateY(0); }
}

.npc-modal-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 20px 20px 0;
}

.npc-modal-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: linear-gradient(135deg, #3b82f6 0%, #6366f1 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  flex-shrink: 0;
}

.npc-modal-body {
  padding: 16px 20px 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.npc-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.npc-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #94a3b8;
}

.npc-input {
  width: 100%;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: rgba(0, 0, 0, 0.3);
  color: #e2e8f0;
  font-size: 13px;
  outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.npc-input:focus {
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.15);
}

.npc-input::placeholder {
  color: #475569;
}

select.npc-input {
  cursor: pointer;
}

select.npc-input option {
  background: #1e293b;
  color: #e2e8f0;
}

.npc-modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  margin-top: 4px;
}

.npc-btn {
  padding: 8px 18px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  border: none;
}

.npc-btn-cancel {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.npc-btn-cancel:hover {
  background: rgba(255, 255, 255, 0.1);
  color: #e2e8f0;
}

.npc-btn-primary {
  background: linear-gradient(135deg, #3b82f6 0%, #6366f1 100%);
  color: white;
}

.npc-btn-primary:hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.npc-btn-primary:disabled {
  opacity: 0.4;
  cursor: not-allowed;
  transform: none;
  box-shadow: none;
}

.npc-btn-secondary {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
  border: 1px dashed rgba(255, 255, 255, 0.12);
  padding: 10px 18px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.npc-btn-secondary:hover {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.3);
  color: #60a5fa;
}
</style>
