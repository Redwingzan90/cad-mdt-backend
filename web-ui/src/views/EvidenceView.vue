<script setup lang="ts">
import { ref, computed, onMounted } from "vue";
import api from "@/api/client";
import { useAuthStore } from "@/stores/auth";

const auth = useAuthStore();
const evidence = ref<any[]>([]);
const loading = ref(false);
const pagination = ref({ page: 1, total: 0, totalPages: 0 });
const showCreateModal = ref(false);

const newEvidence = ref({
  type: "DOCUMENT" as string,
  title: "",
  description: "",
  fileUrl: "",
  caseType: "",
});

async function fetchEvidence(page = 1) {
  loading.value = true;
  try {
    const { data } = await api.get("/evidence", { params: { page, limit: 25 } });
    evidence.value = data.data;
    pagination.value = data.pagination;
  } catch { /* silent */ }
  finally { loading.value = false; }
}

async function createEvidence() {
  try {
    await api.post("/evidence", {
      ...newEvidence.value,
      officerId: auth.user?.officer?.id,
    });
    showCreateModal.value = false;
    newEvidence.value = { type: "DOCUMENT", title: "", description: "", fileUrl: "", caseType: "" };
    fetchEvidence();
  } catch { /* silent */ }
}

const typeConfig: Record<string, { icon: string; badgeClass: string }> = {
  IMAGE: { icon: "🖼️", badgeClass: "premium-badge-image" },
  VIDEO: { icon: "🎬", badgeClass: "premium-badge-video" },
  DOCUMENT: { icon: "📄", badgeClass: "premium-badge-document" },
  NOTE: { icon: "📝", badgeClass: "premium-badge-note" },
  OTHER: { icon: "📦", badgeClass: "premium-badge-other" },
};

const stats = computed(() => {
  const counts: Record<string, number> = {};
  evidence.value.forEach(e => {
    counts[e.type] = (counts[e.type] || 0) + 1;
  });
  return counts;
});

onMounted(() => fetchEvidence());
</script>

<template>
  <div class="p-6 space-y-6 max-w-[1400px] mx-auto">
    <!-- Premium Header -->
    <div class="flex items-start justify-between">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <div class="w-1 h-8 rounded-full gradient-accent"></div>
          <h2 class="text-2xl font-bold text-white tracking-tight">Evidence</h2>
        </div>
        <p class="text-sm text-dark-400 ml-[1.1rem]">Manage and track all evidence items</p>
      </div>
      <button @click="showCreateModal = true" class="premium-btn-primary">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
        Add Evidence
      </button>
    </div>

    <!-- Stats Strip -->
    <div class="flex gap-3 flex-wrap">
      <div v-for="(count, type) in stats" :key="type"
        class="flex items-center gap-2 px-4 py-2 rounded-xl bg-white/[0.03] border border-white/[0.05]">
        <span class="text-base">{{ typeConfig[type]?.icon }}</span>
        <span class="text-xs font-semibold text-dark-200">{{ type }}</span>
        <span class="text-xs text-dark-400 ml-1">{{ count }}</span>
      </div>
    </div>

    <!-- Premium Table -->
    <div class="glass-card-hover overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.06]">
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Evidence #</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Type</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Title</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Officer</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Case</th>
            <th class="px-5 py-4 text-left text-[11px] font-semibold text-dark-400 uppercase tracking-widest">Date</th>
          </tr>
        </thead>
        <tbody>
          <!-- Loading skeleton -->
          <tr v-if="loading">
            <td colspan="6" class="px-5 py-1">
              <div v-for="i in 5" :key="i" class="h-12 rounded-lg shimmer-loading mb-2"></div>
            </td>
          </tr>
          <!-- Empty state -->
          <tr v-else-if="!evidence.length">
            <td colspan="6" class="px-5 py-16 text-center">
              <div class="text-5xl mb-4 opacity-40">📦</div>
              <p class="text-dark-400 font-medium">No evidence found</p>
              <p class="text-dark-500 text-xs mt-1">Add your first evidence item to get started</p>
            </td>
          </tr>
          <!-- Data rows -->
          <tr v-for="e in evidence" :key="e.id" class="premium-table-row cursor-pointer group">
            <td class="px-5 py-4">
              <span class="font-mono text-xs text-dark-300 bg-white/[0.04] px-2.5 py-1 rounded-lg">{{ e.evidenceNumber }}</span>
            </td>
            <td class="px-5 py-4">
              <span :class="typeConfig[e.type]?.badgeClass || 'premium-badge-other'">
                {{ typeConfig[e.type]?.icon }} {{ e.type }}
              </span>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-100 font-medium group-hover:text-white transition-colors">{{ e.title }}</span>
            </td>
            <td class="px-5 py-4">
              <div class="flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-primary-500/20 flex items-center justify-center text-[10px] font-bold text-primary-300">
                  {{ e.officer?.firstName?.[0] }}{{ e.officer?.lastName?.[0] }}
                </div>
                <span class="text-dark-300 text-xs">{{ e.officer?.firstName }} {{ e.officer?.lastName }}</span>
              </div>
            </td>
            <td class="px-5 py-4">
              <span class="font-mono text-xs text-dark-400 bg-white/[0.03] px-2 py-0.5 rounded">{{ e.caseType || "—" }}</span>
            </td>
            <td class="px-5 py-4">
              <span class="text-dark-500 text-xs">{{ new Date(e.createdAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) }}</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Premium Pagination -->
    <div v-if="pagination.totalPages > 1" class="flex items-center justify-center gap-3">
      <button @click="fetchEvidence(pagination.page - 1)" :disabled="pagination.page <= 1"
        class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">
        ← Previous
      </button>
      <div class="flex items-center gap-1.5">
        <button v-for="p in pagination.totalPages" :key="p"
          @click="fetchEvidence(p)"
          class="w-8 h-8 rounded-lg text-xs font-medium transition-all duration-200"
          :class="p === pagination.page
            ? 'bg-primary-500 text-white shadow-lg shadow-primary-500/30'
            : 'text-dark-400 hover:bg-white/[0.05] hover:text-dark-200'">
          {{ p }}
        </button>
      </div>
      <button @click="fetchEvidence(pagination.page + 1)" :disabled="pagination.page >= pagination.totalPages"
        class="premium-btn-secondary text-xs px-4 py-2 disabled:opacity-30">
        Next →
      </button>
    </div>

    <!-- Premium Create Modal -->
    <div v-if="showCreateModal" class="premium-modal-overlay" @click.self="showCreateModal = false">
      <div class="premium-modal-content">
        <!-- Modal Header -->
        <div class="flex items-center gap-3 mb-6">
          <div class="w-10 h-10 rounded-xl gradient-accent flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
          </div>
          <div>
            <h3 class="text-lg font-bold text-white">Add Evidence</h3>
            <p class="text-xs text-dark-400">Log a new evidence item</p>
          </div>
        </div>

        <form @submit.prevent="createEvidence" class="space-y-4">
          <!-- Type Selector -->
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Evidence Type</label>
            <div class="grid grid-cols-5 gap-2">
              <button v-for="(cfg, t) in typeConfig" :key="t" type="button"
                @click="newEvidence.type = t"
                class="flex flex-col items-center gap-1.5 p-3 rounded-xl border transition-all duration-200"
                :class="newEvidence.type === t
                  ? 'bg-primary-500/10 border-primary-500/40 shadow-lg shadow-primary-500/10'
                  : 'bg-white/[0.02] border-white/[0.06] hover:border-white/[0.1] hover:bg-white/[0.04]'">
                <span class="text-xl">{{ cfg.icon }}</span>
                <span class="text-[10px] font-medium" :class="newEvidence.type === t ? 'text-primary-300' : 'text-dark-400'">{{ t }}</span>
              </button>
            </div>
          </div>

          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Title</label>
            <input v-model="newEvidence.title" class="premium-input" placeholder="Evidence title..." required />
          </div>
          <div>
            <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Description</label>
            <textarea v-model="newEvidence.description" class="premium-input" rows="3" placeholder="Describe this evidence..."></textarea>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">File URL</label>
              <input v-model="newEvidence.fileUrl" class="premium-input" placeholder="https://..." />
            </div>
            <div>
              <label class="text-xs font-semibold text-dark-300 mb-2 block uppercase tracking-wider">Case Type</label>
              <input v-model="newEvidence.caseType" class="premium-input" placeholder="e.g. INCIDENT" />
            </div>
          </div>

          <div class="flex justify-end gap-3 pt-4 border-t border-white/[0.06]">
            <button type="button" @click="showCreateModal = false" class="premium-btn-secondary px-5">Cancel</button>
            <button type="submit" class="premium-btn-primary px-6">Add Evidence</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
