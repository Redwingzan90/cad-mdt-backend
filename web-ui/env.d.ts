/// <reference types="vite/client" />

declare module "*.vue" {
  import type { DefineComponent } from "vue";
  const component: DefineComponent<{}, {}, any>;
  export default component;
}

// FiveM NUI message types
interface Window {
  __CNUIMODE__?: boolean;
  invokeNative?: (native: string, ...args: any[]) => void;
  GetParentResourceName?: () => string;
}
