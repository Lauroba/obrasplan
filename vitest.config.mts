import { defineConfig } from "vitest/config";

// Config minima: por ahora las pruebas cubren logica pura (sin DOM/React),
// asi que no hace falta jsdom ni resolver el alias "@/..." de tsconfig.
// Si en el futuro se añaden tests de componentes, ampliar aqui
// (environment: "jsdom" + resolve.alias "@" -> "./src").
export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
