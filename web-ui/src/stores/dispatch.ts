import { defineStore } from "pinia";
import { ref } from "vue";
import api from "@/api/client";
import { getSocket } from "@/api/socket";

export interface DispatchCall {
  id: string;
  callNumber: string;
  type: string;
  description: string;
  location: string;
  lat: number | null;
  lng: number | null;
  priority: string;
  status: string;
  department: { id: string; name: string; code: string };
  creator: { id: string; firstName: string; lastName: string; callsign: string | null };
  assignments: Array<{
    id: string;
    officer: { id: string; firstName: string; lastName: string; callsign: string | null };
    assignedAt: string;
    arrivedAt: string | null;
    clearedAt: string | null;
  }>;
  notes: Array<{ id: string; content: string; createdBy: string; createdAt: string }>;
  createdAt: string;
}

export interface EmergencyCall {
  id: string;
  callerName: string;
  callerPhone: string | null;
  description: string;
  location: string;
  lat: number | null;
  lng: number | null;
  type: string;
  status: string;
  createdAt: string;
}

export const useDispatchStore = defineStore("dispatch", () => {
  const activeCalls = ref<DispatchCall[]>([]);
  const emergencyCalls = ref<EmergencyCall[]>([]);
  const loading = ref(false);

  async function fetchActiveCalls() {
    loading.value = true;
    try {
      const { data } = await api.get("/dispatch/calls/active");
      activeCalls.value = data;
    } catch {
      // Silent fail
    } finally {
      loading.value = false;
    }
  }

  async function fetchEmergencyCalls() {
    try {
      const { data } = await api.get("/emergency?status=PENDING");
      emergencyCalls.value = data.data;
    } catch {
      // Silent fail
    }
  }

  async function createCall(callData: {
    type: string;
    description: string;
    location: string;
    priority: string;
    departmentId: string;
    lat?: number;
    lng?: number;
  }) {
    const { data } = await api.post("/dispatch/calls", callData);
    return data;
  }

  async function updateCall(id: string, updates: Partial<DispatchCall>) {
    const { data } = await api.patch(`/dispatch/calls/${id}`, updates);
    return data;
  }

  async function assignOfficer(callId: string, officerId: string) {
    const { data } = await api.post(`/dispatch/calls/${callId}/assign`, { officerId });
    return data;
  }

  async function unassignOfficer(callId: string, officerId: string) {
    const { data } = await api.post(`/dispatch/calls/${callId}/unassign`, { officerId });
    return data;
  }

  async function addCallNote(callId: string, content: string) {
    const { data } = await api.post(`/dispatch/calls/${callId}/notes`, { content });
    return data;
  }

  function initSocketListeners() {
    const socket = getSocket();

    socket.on("dispatch:call:new", (call: DispatchCall) => {
      activeCalls.value.unshift(call);
    });

    socket.on("dispatch:call:update", (updated: DispatchCall) => {
      const idx = activeCalls.value.findIndex((c) => c.id === updated.id);
      if (idx !== -1) {
        // Merge updates
        activeCalls.value[idx] = { ...activeCalls.value[idx], ...updated };
      }

      // Remove completed/cancelled calls
      if (updated.status === "COMPLETED" || updated.status === "CANCELLED") {
        activeCalls.value = activeCalls.value.filter((c) => c.id !== updated.id);
      }
    });

    socket.on("dispatch:call:note", ({ callId, note }: { callId: string; note: any }) => {
      const call = activeCalls.value.find((c) => c.id === callId);
      if (call) {
        call.notes = call.notes || [];
        call.notes.unshift(note);
      }
    });

    socket.on("emergency:new", (call: EmergencyCall) => {
      emergencyCalls.value.unshift(call);
    });

    socket.on("emergency:update", (updated: EmergencyCall) => {
      const idx = emergencyCalls.value.findIndex((c) => c.id === updated.id);
      if (idx !== -1) {
        emergencyCalls.value[idx] = { ...emergencyCalls.value[idx], ...updated };
      }
      if (updated.status !== "PENDING") {
        emergencyCalls.value = emergencyCalls.value.filter((c) => c.id !== updated.id);
      }
    });
  }

  return {
    activeCalls,
    emergencyCalls,
    loading,
    fetchActiveCalls,
    fetchEmergencyCalls,
    createCall,
    updateCall,
    assignOfficer,
    unassignOfficer,
    addCallNote,
    initSocketListeners,
  };
});
