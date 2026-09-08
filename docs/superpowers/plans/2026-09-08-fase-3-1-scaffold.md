# Meridiano — Fase 3.1 — Scaffold, shell e acesso: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md`. Cada task traz `Files:` e `Depends-on:`. Implementadores **não commitam**; reportam os arquivos tocados. O controlador commita uma task por vez, no repo certo (`frontend/` = `meridiano-app`, `backend/` = `meridiano-api`). Task 1 instala **todas** as dependências e scripts do `package.json` para que nenhuma task posterior toque esse arquivo.

**Goal:** SPA React buildada e servida pela API, com login real por cookie, sidebar por permissão, telas de acesso (login, definir senha, esqueci senha, redefinir senha), componentes-base do contrato até `Section`, styleguide em `/styleguide`, lint/typecheck/test/CI verdes e regressão visual mínima — a base sobre a qual 3.2 (Nova viagem) é construída.

**Architecture:** `frontend/` (Vite + React 19 + TS strict) com CSS Modules consumindo só `src/styles/tokens.css`; `src/api/http.ts` traduz ProblemDetails em erros de UX; `AuthProvider` carrega `/auth/me` (agora com `permissoes[]`); `AppShell` = Sidebar por configuração + GlobalHeader + Page. Backend: `/auth/me` devolve permissões, `GET /auth/tokens/{token}` valida convite/reset, `AddModules` separa registro de módulos de `AddAuth`, `UseInfra` serve `wwwroot/` com fallback SPA que não engole `/api`. Dockerfile ganha estágio Node.

**Tech Stack:** React 19 · react-router 7 (`react-router` pacote único, modo declarativo) · @tanstack/react-query 5 · react-hook-form 7 · lucide-react · @fontsource-variable/manrope · Vite 6 · TypeScript 5 strict · Vitest + @testing-library/react + jsdom · Playwright · ESLint 9 flat + typescript-eslint (type-aware) + react-hooks + jsx-a11y · Biome (format + regras curadas) · .NET 10.

**Spec:** `docs/design-system-contrato.md` (§2 escalas, §3 componentes e regras de API, §4 erros e estado, §5 proibido, §6 a11y, §7 qualidade) · `docs/design/prototipo-v1.html` telas 01–04 e shell · `regras-e-escopo-v2.md` §6.1 (estados), §7 (perfis) · `docs/superpowers/plans/2026-09-08-fase-3-master.md` (restrições globais).

## Global Constraints

- Node 24, npm 12. `package-lock.json` commitado. Versões: instalar com `npm install <pkg>` sem pin manual; o lock fixa.
- TS `strict: true`, `noUncheckedIndexedAccess: true`, `verbatimModuleSyntax: true`. Zero `any`.
- CSS: só CSS Modules (`*.module.css`) + `src/styles/tokens.css` + `src/styles/global.css`. Proibido em qualquer arquivo que não seja `tokens.css`: cor hex (`#[0-9a-f]{3,8}`), `font-size:`, `@media` com largura fora de `1024px`/`1280px`/`1440px`. `scripts/check-tokens.mjs` falha o lint se achar.
- Ícones só de `lucide-react`. Tamanhos via `--icon-inline` 16 · `--icon-nav` 18 · `--icon-button` 20.
- Textos de interface em português; nomes de arquivo, componentes e props em inglês (`Button`, `Field`), nomes de domínio em português (`apresentacaoStatus`, `permissoes`).
- Componentes recebem intenção: `variant` (`business` `primary` `secondary` `tertiary` `danger`), `tone` (`info` `success` `warning` `danger` `neutral`), `calculated`, `readOnly`, `disabled`. Nenhuma prop de cor, tamanho em px ou margem.
- Máximo 350 linhas por arquivo (`eslint max-lines`).
- Front nunca protege nada: `permissoes[]` só esconde. Backend continua com `.RequerPermissao`.
- Backend: `Program.cs` não muda. `TreatWarningsAsErrors=true`. Testes de integração em `tests/Meridiano.Api.Tests` (coleção `db`), rodar com Docker.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T01, T06 | T01 cria o projeto front (todas as deps e scripts); T06 é só backend (repo diferente) |
| 1 | T02, T03, T04, T05, T07 | Dependem só de T01; arquivos disjuntos |
| 2 | T08 | Toast/Modal usam `Button` (T04); `useSalvamento` usa erros (T03) |
| 3 | T09 | Telas de acesso usam http (T03), Field/Input/Button (T04), Alert (T05), toast (T08) e contrato de `/auth/me` (T06) |
| 4 | T10 | AppShell usa AuthProvider (T09), primitivos e feedback |
| 5 | T11 | Styleguide + Playwright usam tudo |
| 6 | T12 | Docs e CI finais |

---

### Task 1: Projeto Vite + React + TS, dependências, scripts, fonte, CSS global

**Files:**
- Create: `frontend/package.json`, `frontend/package-lock.json`, `frontend/vite.config.ts`, `frontend/tsconfig.json`, `frontend/tsconfig.node.json`, `frontend/index.html`, `frontend/.gitignore`, `frontend/.npmrc`
- Create: `frontend/src/main.tsx`, `frontend/src/App.tsx`, `frontend/src/vite-env.d.ts`, `frontend/src/styles/global.css`, `frontend/src/test/setup.ts`, `frontend/src/App.test.tsx`
- Modify: `frontend/src/styles/tokens.css` — **uma linha só**: acrescentar `--color-text-on-dark-muted` (o contrato §4.5 cita o token, mas ele não existe no arquivo; sem isso a arte do login precisa de cor solta)

**Depends-on:** none

**Interfaces:**
- Produces: scripts `dev` `build` `preview` `typecheck` `lint` `lint:eslint` `lint:biome` `lint:tokens` `format` `test` `test:e2e`; alias `@/` → `src/`; proxy `/api` e `/health` → `http://localhost:5000`; `global.css` importa `tokens.css` e a fonte Manrope e aplica reset.

- [ ] **Step 1: Criar o projeto**

```bash
cd frontend
npm create vite@latest . -- --template react-ts
# responder "Ignore files and continue" para manter README.md e src/styles/tokens.css
rm -rf src/assets src/App.css src/index.css public/vite.svg
```

- [ ] **Step 2: Instalar todas as dependências (runtime e dev) de uma vez**

```bash
npm install react react-dom react-router @tanstack/react-query react-hook-form lucide-react @fontsource-variable/manrope
npm install -D typescript vite @vitejs/plugin-react vitest jsdom @testing-library/react @testing-library/user-event @testing-library/jest-dom @types/react @types/react-dom @types/node eslint @eslint/js typescript-eslint eslint-plugin-react-hooks eslint-plugin-jsx-a11y eslint-plugin-react-refresh @biomejs/biome @playwright/test
```

- [ ] **Step 3: `package.json` — scripts finais (nenhuma task posterior edita este arquivo)**

```json
{
  "name": "meridiano-app",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "typecheck": "tsc -b --noEmit",
    "lint": "npm run lint:eslint && npm run lint:biome && npm run lint:tokens",
    "lint:eslint": "eslint .",
    "lint:biome": "biome check .",
    "lint:tokens": "node scripts/check-tokens.mjs",
    "format": "biome format --write .",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "playwright test"
  }
}
```

(Manter as seções `dependencies`/`devDependencies` geradas pelo `npm install`.)

- [ ] **Step 4: `.npmrc`, `.gitignore`**

`.npmrc`:
```
save-exact=false
fund=false
audit=false
```

`.gitignore` (acrescentar ao gerado):
```
node_modules
dist
test-results
playwright-report
.vite
```

- [ ] **Step 5: `vite.config.ts`**

```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:5000",
      "/health": "http://localhost:5000",
    },
  },
  build: { outDir: "dist", sourcemap: true },
  css: { modules: { localsConvention: "camelCaseOnly" } },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    css: { modules: { classNameStrategy: "non-scoped" } },
  },
});
```

- [ ] **Step 6: `tsconfig.json` / `tsconfig.node.json`**

`tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "verbatimModuleSyntax": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "noEmit": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"],
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src", "e2e", "scripts"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

`tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "composite": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "types": ["node"],
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts", "playwright.config.ts"]
}
```

- [ ] **Step 7: `index.html`, `main.tsx`, `App.tsx`, `global.css`, `setup.ts`, token faltante**

Em `src/styles/tokens.css`, logo abaixo da linha `--color-text-inverse: ...;`, acrescentar:
```css
  --color-text-on-dark-muted: rgb(255 255 255 / 0.78); /* texto secundário sobre navy (login, sidebar) */
```
Nada mais muda em `tokens.css`.

`index.html`:
```html
<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Meridiano</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

`src/main.tsx`:
```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource-variable/manrope";
import "./styles/global.css";
import { App } from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```

`src/App.tsx` (placeholder; T09 substitui pelo router):
```tsx
export function App() {
  return <h1>Meridiano</h1>;
}
```

`src/styles/global.css`:
```css
@import "./tokens.css";

*,
*::before,
*::after {
  box-sizing: border-box;
}

html {
  font: var(--type-body);
  font-family: var(--font-ui);
  color: var(--color-text-primary);
  background: var(--color-bg-page);
  -webkit-font-smoothing: antialiased;
}

body {
  margin: 0;
  min-height: 100vh;
}

h1,
h2,
h3,
p {
  margin: 0;
}

button,
input,
select,
textarea {
  font: inherit;
  color: inherit;
}

a {
  color: var(--color-text-link);
}

:focus-visible {
  outline: 2px solid var(--color-focus);
  outline-offset: 2px;
}

.tabular {
  font-variant-numeric: tabular-nums;
}
```

`src/test/setup.ts`:
```ts
import "@testing-library/jest-dom/vitest";
```

- [ ] **Step 8: Teste de fumaça**

`src/App.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { App } from "./App";

test("renderiza o nome do produto", () => {
  render(<App />);
  expect(screen.getByRole("heading", { name: "Meridiano" })).toBeInTheDocument();
});
```

- [ ] **Step 9: Verificar**

Run: `cd frontend && npm run typecheck && npm run test && npm run build`
Expected: typecheck sem erro; 1 teste passa; `dist/index.html` existe. (`npm run lint` ainda falha: configs chegam em T02 — esperado.)

- [ ] **Step 10: Reportar arquivos tocados (controlador commita)**

Commit sugerido (repo `frontend/`): `chore: scaffold vite + react + ts with all deps, tokens and global css`

---

### Task 2: Quality gates — ESLint, Biome, lint de tokens, CI

**Files:**
- Create: `frontend/eslint.config.js`, `frontend/biome.json`, `frontend/scripts/check-tokens.mjs`, `frontend/scripts/check-tokens.test.mjs`, `frontend/.github/workflows/ci.yml`

**Depends-on:** T01

**Interfaces:**
- Produces: `npm run lint` verde no repo vazio; CI roda lint, typecheck, test, build.

- [ ] **Step 1: `eslint.config.js`**

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import jsxA11y from "eslint-plugin-jsx-a11y";

export default tseslint.config(
  { ignores: ["dist", "node_modules", "playwright-report", "test-results", "*.config.*"] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  jsxA11y.flatConfigs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } },
    plugins: { "react-hooks": reactHooks, "react-refresh": reactRefresh },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      "max-lines": ["error", { max: 350, skipBlankLines: true, skipComments: true }],
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/restrict-template-expressions": ["error", { allowNumber: true }],
      "no-restricted-globals": ["error", "alert", "confirm", "prompt"],
      "no-restricted-imports": ["error", { patterns: [{ group: ["react-icons", "@heroicons/*", "@mui/*"], message: "Só lucide-react (contrato §2)." }] }],
    },
  },
  {
    files: ["**/*.test.{ts,tsx}", "e2e/**"],
    rules: { "@typescript-eslint/no-non-null-assertion": "off", "@typescript-eslint/no-floating-promises": "off" },
  },
);
```

- [ ] **Step 2: `biome.json` (formatação + conjunto pequeno; sem sobrepor ESLint)**

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "files": { "ignore": ["dist", "node_modules", "playwright-report", "test-results", "package-lock.json"] },
  "formatter": { "enabled": true, "indentStyle": "space", "indentWidth": 2, "lineWidth": 120 },
  "javascript": { "formatter": { "quoteStyle": "double", "trailingCommas": "all", "semicolons": "always" } },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": false,
      "correctness": { "noUnusedImports": "error", "noUnusedVariables": "error" },
      "suspicious": { "noDebugger": "error", "noConsole": { "level": "error", "options": { "allow": ["warn", "error"] } } },
      "style": { "useConst": "error", "noNonNullAssertion": "off" }
    }
  },
  "organizeImports": { "enabled": true }
}
```

(Se a versão instalada do Biome for 1.x, trocar o `$schema` para `https://biomejs.dev/schemas/1.9.4/schema.json` e `"files": { "ignore": ... }` funciona igual; em 2.x usar `"includes": ["**", "!dist", ...]`. Rodar `npx biome migrate --write` resolve.)

- [ ] **Step 3: Teste do lint de tokens (falha antes de existir o script)**

`scripts/check-tokens.test.mjs`:
```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { violacoes } from "./check-tokens.mjs";

test("hex fora de tokens.css é violação", () => {
  const v = violacoes("src/x.module.css", ".a{color:#fff}");
  assert.equal(v.length, 1);
  assert.match(v[0], /hex/);
});

test("tokens.css pode ter hex e font-size", () => {
  assert.equal(violacoes("src/styles/tokens.css", ".a{color:#fff;font-size:14px}").length, 0);
});

test("font-size solto é violação; font: var(--type-*) não é", () => {
  assert.equal(violacoes("src/a.module.css", ".a{font-size:13px}").length, 1);
  assert.equal(violacoes("src/a.module.css", ".a{font:var(--type-label)}").length, 0);
});

test("@media só com 1024, 1280 ou 1440", () => {
  assert.equal(violacoes("src/a.module.css", "@media (max-width:1366px){.a{display:none}}").length, 1);
  assert.equal(violacoes("src/a.module.css", "@media (max-width:1279px){.a{display:none}}").length, 1);
  assert.equal(violacoes("src/a.module.css", "@media (max-width:1280px){.a{display:none}}").length, 0);
});

test("style={{color:'#'}} em tsx é violação", () => {
  assert.equal(violacoes("src/A.tsx", "<div style={{ color: '#5396d1' }} />").length, 1);
});
```

- [ ] **Step 4: Rodar para ver falhar**

Run: `cd frontend && node --test scripts/`
Expected: FAIL — `Cannot find module './check-tokens.mjs'`

- [ ] **Step 5: `scripts/check-tokens.mjs`**

```js
// Lint do contrato de design (§5): sem hex, font-size solto ou @media fora dos breakpoints
// em qualquer arquivo de src/ exceto src/styles/tokens.css.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const ISENTO = /styles[\\/]tokens\.css$/;
const HEX = /#[0-9a-fA-F]{3,8}\b/g;
const FONT_SIZE = /font-size\s*:/g;
const MEDIA = /@media[^{]*?(\d+)px/g;
const BREAKPOINTS = new Set(["1024", "1280", "1440"]);

export function violacoes(caminho, conteudo) {
  if (ISENTO.test(caminho)) return [];
  const achados = [];
  for (const m of conteudo.matchAll(HEX)) achados.push(`${caminho}: hex ${m[0]} — use var(--color-*)`);
  if (/\.css$/.test(caminho)) {
    for (const _ of conteudo.matchAll(FONT_SIZE)) achados.push(`${caminho}: font-size solto — use font: var(--type-*)`);
    for (const m of conteudo.matchAll(MEDIA)) {
      if (!BREAKPOINTS.has(m[1])) achados.push(`${caminho}: @media ${m[1]}px — só 1024, 1280 ou 1440`);
    }
  }
  return achados;
}

function* arquivos(dir) {
  for (const nome of readdirSync(dir)) {
    const p = join(dir, nome);
    if (statSync(p).isDirectory()) yield* arquivos(p);
    else if (/\.(css|tsx?)$/.test(nome) && !/\.test\.tsx?$/.test(nome)) yield p;
  }
}

if (process.argv[1] && /check-tokens\.mjs$/.test(process.argv[1])) {
  const todas = [];
  for (const arq of arquivos("src")) todas.push(...violacoes(arq, readFileSync(arq, "utf8")));
  if (todas.length) {
    console.error(todas.join("\n"));
    process.exit(1);
  }
  console.log("tokens ok");
}
```

- [ ] **Step 6: Rodar tudo**

Run: `cd frontend && node --test scripts/ && npm run lint && npm run typecheck`
Expected: 5 testes passam; `eslint .` sem erro; `biome check .` sem erro (rodar `npm run format` antes se reclamar de formatação dos arquivos da T01); `tokens ok`.

- [ ] **Step 7: CI**

`.github/workflows/ci.yml`:
```yaml
name: ci
on:
  push:
    branches: [main, develop]
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist
```

(Playwright entra no CI na T11.)

- [ ] **Step 8: Reportar arquivos tocados**

Commit sugerido: `chore: eslint + biome + design-token lint + ci`

---

### Task 3: Cliente HTTP e modelo de erros de UX

**Files:**
- Create: `frontend/src/api/errors.ts`, `frontend/src/api/http.ts`, `frontend/src/api/http.test.ts`, `frontend/src/api/queryClient.ts`

**Depends-on:** T01

**Interfaces:**
- Produces:
  - `class ApiError extends Error { status: number; codigo: string; detalhe: string; extensions: Record<string, unknown> }`
  - `class ValidationError extends ApiError` (422) · `class ConflictError extends ApiError` (409) · `class PermissionError extends ApiError` (403) · `class UnauthenticatedError extends ApiError` (401) · `class NotFoundError extends ApiError` (404) · `class NetworkError extends Error`
  - `api.get<T>(path): Promise<T>` · `api.post<T>(path, body?): Promise<T>` · `api.put<T>(path, body): Promise<T>` · `api.delete(path): Promise<void>` — `path` relativo a `/api/v1`, ex. `api.get<Me>("/auth/me")`
  - `queryClient: QueryClient` (retry 0 em 4xx, 1 em rede; `staleTime` 30 s)
  - `mensagemDeErro(e: unknown): string` — texto para o usuário (nunca "HTTP 409")

- [ ] **Step 1: Testes**

`src/api/http.test.ts`:
```ts
import { api, mensagemDeErro } from "./http";
import { ConflictError, NetworkError, UnauthenticatedError, ValidationError } from "./errors";

function respostaProblem(status: number, body: object) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/problem+json" } });
}

beforeEach(() => vi.restoreAllMocks());

test("GET devolve JSON e envia credenciais", async () => {
  const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ nome: "x" }), { status: 200, headers: { "content-type": "application/json" } }));
  const r = await api.get<{ nome: string }>("/auth/me");
  expect(r.nome).toBe("x");
  expect(spy).toHaveBeenCalledWith("/api/v1/auth/me", expect.objectContaining({ method: "GET", credentials: "same-origin" }));
});

test("204 devolve undefined", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 204 }));
  await expect(api.post("/auth/logout")).resolves.toBeUndefined();
});

test("422 vira ValidationError com codigo", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(respostaProblem(422, { status: 422, title: "Regra de negócio", detail: "Senha curta", codigo: "senha_curta" }));
  const e = await api.post("/auth/definir-senha", {}).catch((x: unknown) => x);
  expect(e).toBeInstanceOf(ValidationError);
  expect((e as ValidationError).codigo).toBe("senha_curta");
  expect(mensagemDeErro(e)).toBe("Senha curta");
});

test("409 vira ConflictError com mensagem de recarregar", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(respostaProblem(409, { status: 409, detail: "alterado", codigo: "conflito_concorrencia" }));
  const e = await api.put("/usuarios/1", {}).catch((x: unknown) => x);
  expect(e).toBeInstanceOf(ConflictError);
  expect(mensagemDeErro(e)).toMatch(/Recarregue/);
});

test("401 sem corpo vira UnauthenticatedError", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 401 }));
  await expect(api.get("/auth/me")).rejects.toBeInstanceOf(UnauthenticatedError);
});

test("falha de rede vira NetworkError", async () => {
  vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("Failed to fetch"));
  const e = await api.get("/x").catch((x: unknown) => x);
  expect(e).toBeInstanceOf(NetworkError);
  expect(mensagemDeErro(e)).toMatch(/Sem conexão/);
});
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `cd frontend && npx vitest run src/api`
Expected: FAIL — módulo `./http` não existe.

- [ ] **Step 3: `errors.ts`**

```ts
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly codigo: string,
    public readonly detalhe: string,
    public readonly extensions: Record<string, unknown> = {},
  ) {
    super(detalhe);
    this.name = new.target.name;
  }
}
export class ValidationError extends ApiError {}
export class ConflictError extends ApiError {}
export class PermissionError extends ApiError {}
export class UnauthenticatedError extends ApiError {}
export class NotFoundError extends ApiError {}
export class NetworkError extends Error {
  constructor() {
    super("Sem conexão");
    this.name = "NetworkError";
  }
}

interface ProblemDetails {
  status?: number;
  title?: string;
  detail?: string;
  codigo?: string;
  [k: string]: unknown;
}

export function erroDeResposta(status: number, problem: ProblemDetails | null): ApiError {
  const codigo = problem?.codigo ?? "erro";
  const detalhe = problem?.detail ?? problem?.title ?? "Erro inesperado";
  const { status: _s, title: _t, detail: _d, codigo: _c, ...extensions } = problem ?? {};
  switch (status) {
    case 401: return new UnauthenticatedError(status, "nao_autenticado", "Sessão expirada", extensions);
    case 403: return new PermissionError(status, codigo, detalhe, extensions);
    case 404: return new NotFoundError(status, codigo, detalhe, extensions);
    case 409: return new ConflictError(status, codigo, detalhe, extensions);
    case 422: return new ValidationError(status, codigo, detalhe, extensions);
    default: return new ApiError(status, codigo, detalhe, extensions);
  }
}

export function mensagemDeErro(e: unknown): string {
  if (e instanceof NetworkError) return "Sem conexão. Verifique a internet e tente de novo.";
  if (e instanceof ConflictError) return "Alguém alterou este registro enquanto você editava. Recarregue e tente de novo.";
  if (e instanceof PermissionError) return "Você não tem permissão para isso.";
  if (e instanceof UnauthenticatedError) return "Sua sessão expirou. Entre de novo.";
  if (e instanceof ApiError) return e.detalhe;
  return "Erro inesperado. Tente de novo.";
}
```

- [ ] **Step 4: `http.ts`**

```ts
import { erroDeResposta, NetworkError } from "./errors";
export { mensagemDeErro } from "./errors";

const BASE = "/api/v1";

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let resposta: Response;
  try {
    resposta = await fetch(`${BASE}${path}`, {
      method,
      credentials: "same-origin",
      headers: body === undefined ? { Accept: "application/json" } : { Accept: "application/json", "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new NetworkError();
  }
  if (resposta.status === 204) return undefined as T;
  const tipo = resposta.headers.get("content-type") ?? "";
  const json = tipo.includes("json") ? ((await resposta.json()) as unknown) : null;
  if (!resposta.ok) throw erroDeResposta(resposta.status, json as Parameters<typeof erroDeResposta>[1]);
  return json as T;
}

export const api = {
  get: <T>(path: string) => request<T>("GET", path),
  post: <T = void>(path: string, body?: unknown) => request<T>("POST", path, body),
  put: <T = void>(path: string, body: unknown) => request<T>("PUT", path, body),
  delete: (path: string) => request<void>("DELETE", path),
};
```

- [ ] **Step 5: `queryClient.ts`**

```ts
import { QueryClient } from "@tanstack/react-query";
import { ApiError, NetworkError } from "./errors";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: false,
      retry: (count, e) => e instanceof NetworkError && count < 1,
      throwOnError: (e) => e instanceof ApiError && e.status === 401,
    },
    mutations: { retry: 0 },
  },
});
```

- [ ] **Step 6: Rodar**

Run: `cd frontend && npx vitest run src/api && npm run lint`
Expected: 6 testes passam; lint verde.

- [ ] **Step 7: Reportar arquivos tocados**

Commit sugerido: `feat(api): http client with problem-details error model`

---

### Task 4: Primitivos de formulário — Button, IconButton, Field, Input, Select, Checkbox, Radio, DateInput, MoneyInput, MoneyValue, dinheiro util

**Files:**
- Create: `frontend/src/lib/dinheiro.ts`, `frontend/src/lib/dinheiro.test.ts`, `frontend/src/lib/cx.ts`
- Create: `frontend/src/components/Button/Button.tsx`, `Button.module.css`, `Button.test.tsx`, `IconButton.tsx`
- Create: `frontend/src/components/Field/Field.tsx`, `Field.module.css`, `Field.test.tsx`, `FieldContext.ts`
- Create: `frontend/src/components/Input/Input.tsx`, `Input.module.css`, `Select.tsx`, `Checkbox.tsx`, `Radio.tsx`, `DateInput.tsx`, `MoneyInput.tsx`, `MoneyInput.test.tsx`, `MoneyValue.tsx`
- Create: `frontend/src/components/index.ts` (barrel só destes; T05/T08 acrescentam os seus em arquivos próprios — ver Interfaces)

**Depends-on:** T01

**Interfaces:**
- Produces:
  - `cx(...classes: (string | false | undefined)[]): string`
  - `formatarDinheiro(valor: number | null | undefined): string` → `"R$ 1.234,56"`, `"−R$ 10,00"` (sinal U+2212), `""` para nulo · `parsearDinheiro(texto: string): number | null`
  - `<Button variant="business"|"primary"|"secondary"|"tertiary"|"danger" size?="md"|"sm" loading?: boolean icon?: ReactNode type? onClick? disabled?>children</Button>` — nunca cor.
  - `<IconButton label: string icon: ReactNode variant?="secondary"|"tertiary" onClick? />` (`aria-label` obrigatório)
  - `<Field label: string required? helper? tooltip? error?: string htmlFor?>{control}</Field>` — injeta `id`, `aria-describedby`, `aria-invalid` no filho via `FieldContext` (`useField()` devolve `{ id, describedBy, invalid }`).
  - `<Input calculated? readOnly? disabled? …InputHTMLAttributes />`, `<Select options: {value: string; label: string}[] placeholder? …/>`, `<Checkbox label />`, `<Radio label />`, `<DateInput />` (nativo `type="date"`), `<MoneyInput value: number | null onChange(v: number | null) calculated? readOnly? allowNegative? />`, `<MoneyValue value: number | null emphasis?="normal"|"result" tone?="normal"|"above"|"negative" />`.
  - `src/components/index.ts` exporta tudo acima. Convenção para T05/T08/T10: cada task cria **seu próprio barrel** (`src/components/feedback.ts`, `src/components/shell.ts`) para não editar este arquivo.

- [ ] **Step 1: Teste do util de dinheiro**

`src/lib/dinheiro.test.ts`:
```ts
import { formatarDinheiro, parsearDinheiro } from "./dinheiro";

test("formata pt-BR com duas casas", () => {
  expect(formatarDinheiro(1234.5)).toBe("R$ 1.234,50");
  expect(formatarDinheiro(0)).toBe("R$ 0,00");
  expect(formatarDinheiro(-10)).toBe("−R$ 10,00");
  expect(formatarDinheiro(null)).toBe("");
});

test("parseia o que a pessoa digita", () => {
  expect(parsearDinheiro("1.234,56")).toBe(1234.56);
  expect(parsearDinheiro("R$ 1.234,56")).toBe(1234.56);
  expect(parsearDinheiro("1234,5")).toBe(1234.5);
  expect(parsearDinheiro("1234")).toBe(1234);
  expect(parsearDinheiro("-50,00")).toBe(-50);
  expect(parsearDinheiro("")).toBeNull();
  expect(parsearDinheiro("abc")).toBeNull();
});
```

- [ ] **Step 2: Rodar para ver falhar** — `npx vitest run src/lib` → FAIL (módulo não existe).

- [ ] **Step 3: `lib/dinheiro.ts` e `lib/cx.ts`**

```ts
// dinheiro.ts
const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", minimumFractionDigits: 2, maximumFractionDigits: 2 });

export function formatarDinheiro(valor: number | null | undefined): string {
  if (valor === null || valor === undefined || Number.isNaN(valor)) return "";
  const texto = fmt.format(Math.abs(valor)).replace(/ /g, " ");
  return valor < 0 ? `−${texto}` : texto;
}

export function parsearDinheiro(texto: string): number | null {
  const limpo = texto.replace(/[R$\s−]/g, "").replace(/\./g, "").replace(",", ".");
  if (limpo === "" || limpo === "-") return null;
  const n = Number(limpo);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}
```

```ts
// cx.ts
export const cx = (...classes: (string | false | null | undefined)[]) => classes.filter(Boolean).join(" ");
```

- [ ] **Step 4: Testes de Button e Field**

`src/components/Button/Button.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { Button } from "./Button";

test("variant vira classe, nunca estilo inline", () => {
  render(<Button variant="business">Salvar viagem</Button>);
  const b = screen.getByRole("button", { name: "Salvar viagem" });
  expect(b.className).toContain("business");
  expect(b.getAttribute("style")).toBeNull();
});

test("loading desabilita e anuncia", () => {
  render(<Button variant="primary" loading>Salvando…</Button>);
  const b = screen.getByRole("button");
  expect(b).toBeDisabled();
  expect(b).toHaveAttribute("aria-busy", "true");
});
```

`src/components/Field/Field.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { Field } from "./Field";
import { Input } from "../Input/Input";

test("liga label, helper e erro ao controle", () => {
  render(
    <Field label="E-mail" required helper="Use o e-mail do convite" error="E-mail inválido">
      <Input />
    </Field>,
  );
  const input = screen.getByLabelText(/E-mail/);
  expect(input).toHaveAttribute("aria-invalid", "true");
  const ids = input.getAttribute("aria-describedby")!.split(" ");
  expect(ids).toHaveLength(2);
  expect(screen.getByText("E-mail inválido")).toHaveAttribute("role", "alert");
});
```

- [ ] **Step 5: Rodar para ver falhar** — `npx vitest run src/components` → FAIL.

- [ ] **Step 6: Button**

`Button.module.css`:
```css
.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  height: var(--control-h);
  padding: 0 var(--space-4);
  border: 1px solid transparent;
  border-radius: var(--control-radius);
  font: var(--type-label);
  cursor: pointer;
  white-space: nowrap;
}
.sm { height: var(--control-h-sm); padding: 0 var(--space-3); }
.button:disabled { opacity: 0.6; cursor: not-allowed; }
.business { background: var(--color-action-business); color: var(--color-text-inverse); }
.business:hover:not(:disabled) { background: var(--color-action-business-hover); }
.primary { background: var(--color-action); color: var(--color-text-inverse); }
.primary:hover:not(:disabled) { background: var(--color-action-hover); }
.secondary { background: var(--color-bg-surface); border-color: var(--color-border-strong); color: var(--color-text-primary); }
.secondary:hover:not(:disabled) { background: var(--color-bg-subtle); }
.tertiary { background: transparent; color: var(--color-text-link); padding: 0 var(--space-2); }
.tertiary:hover:not(:disabled) { background: var(--color-bg-subtle); }
.danger { background: var(--color-danger); color: var(--color-text-inverse); }
.iconOnly { width: var(--control-h); padding: 0; }
.spinner {
  width: var(--icon-inline);
  height: var(--icon-inline);
  border: 2px solid currentColor;
  border-right-color: transparent;
  border-radius: var(--radius-pill);
  animation: girar 0.7s linear infinite;
}
@keyframes girar { to { transform: rotate(360deg); } }
```

`Button.tsx`:
```tsx
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "@/lib/cx";
import s from "./Button.module.css";

export type ButtonVariant = "business" | "primary" | "secondary" | "tertiary" | "danger";

export interface ButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "style"> {
  variant: ButtonVariant;
  size?: "md" | "sm";
  loading?: boolean;
  icon?: ReactNode;
}

export function Button({ variant, size = "md", loading = false, icon, children, className, disabled, type = "button", ...rest }: ButtonProps) {
  return (
    <button
      type={type}
      className={cx(s.button, s[variant], size === "sm" && s.sm, className)}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <span className={s.spinner} aria-hidden /> : icon}
      {children}
    </button>
  );
}
```

`IconButton.tsx`:
```tsx
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "@/lib/cx";
import s from "./Button.module.css";

interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "style" | "children"> {
  label: string;
  icon: ReactNode;
  variant?: "secondary" | "tertiary";
}

export function IconButton({ label, icon, variant = "tertiary", className, type = "button", ...rest }: IconButtonProps) {
  return (
    <button type={type} aria-label={label} title={label} className={cx(s.button, s[variant], s.iconOnly, className)} {...rest}>
      {icon}
    </button>
  );
}
```

- [ ] **Step 7: Field + FieldContext**

`FieldContext.ts`:
```ts
import { createContext, useContext } from "react";

export interface FieldInfo { id: string; describedBy?: string; invalid: boolean; required: boolean }
export const FieldContext = createContext<FieldInfo | null>(null);
export const useField = () => useContext(FieldContext);
```

`Field.module.css`:
```css
.field { display: flex; flex-direction: column; gap: var(--space-2); min-width: 0; }
.label { font: var(--type-label); color: var(--color-text-secondary); display: inline-flex; gap: var(--space-1); align-items: center; }
.required { color: var(--color-danger-text); }
.helper { font: var(--type-helper); color: var(--color-text-muted); }
.error { font: var(--type-helper); color: var(--color-danger-text); }
.tooltip { color: var(--color-text-muted); display: inline-flex; }
```

`Field.tsx`:
```tsx
import { useId, type ReactNode } from "react";
import { CircleHelp } from "lucide-react";
import { FieldContext } from "./FieldContext";
import s from "./Field.module.css";

export interface FieldProps {
  label: string;
  required?: boolean;
  helper?: string;
  tooltip?: string;
  error?: string;
  children: ReactNode;
  className?: string;
}

export function Field({ label, required = false, helper, tooltip, error, children, className }: FieldProps) {
  const id = useId();
  const helperId = helper ? `${id}-helper` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  const describedBy = [helperId, errorId].filter(Boolean).join(" ") || undefined;
  return (
    <div className={[s.field, className].filter(Boolean).join(" ")}>
      <label htmlFor={id} className={s.label}>
        {label}
        {required && <span className={s.required} aria-hidden>*</span>}
        {tooltip && (
          <span className={s.tooltip} title={tooltip} aria-label={tooltip} role="img">
            <CircleHelp size={16} />
          </span>
        )}
      </label>
      <FieldContext.Provider value={{ id, describedBy, invalid: Boolean(error), required }}>{children}</FieldContext.Provider>
      {helper && !error && <span id={helperId} className={s.helper}>{helper}</span>}
      {error && <span id={errorId} role="alert" className={s.error}>{error}</span>}
    </div>
  );
}
```

- [ ] **Step 8: Input, Select, Checkbox, Radio, DateInput**

`Input.module.css`:
```css
.control {
  height: var(--control-h);
  width: 100%;
  padding: 0 var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--control-radius);
  background: var(--field-editable-bg);
  font: var(--type-body);
  color: var(--color-text-primary);
}
.control:focus { outline: 2px solid var(--color-focus); outline-offset: -1px; border-color: var(--color-action); }
.control[aria-invalid="true"] { border-color: var(--field-error-border); }
.control:disabled { background: var(--field-disabled-bg); color: var(--field-disabled-text); cursor: not-allowed; }
.calculated { background: var(--field-calc-bg); border-color: var(--field-calc-border); }
.readOnly { background: var(--field-readonly-bg); border-color: transparent; }
.money { text-align: right; font-variant-numeric: tabular-nums; }
.check { display: inline-flex; align-items: center; gap: var(--space-2); min-height: var(--control-h); font: var(--type-body); cursor: pointer; }
.check input { width: var(--icon-inline); height: var(--icon-inline); accent-color: var(--color-action); margin: 0; }
.wrap { position: relative; }
.calcBadge {
  position: absolute; right: var(--space-2); top: 50%; transform: translateY(-50%);
  font: var(--type-caption); letter-spacing: var(--tracking-caps); text-transform: uppercase; color: var(--color-text-muted);
  pointer-events: none;
}
```

`Input.tsx`:
```tsx
import { forwardRef, type InputHTMLAttributes } from "react";
import { cx } from "@/lib/cx";
import { useField } from "../Field/FieldContext";
import s from "./Input.module.css";

export interface InputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "style" | "size"> {
  calculated?: boolean;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(function Input({ calculated, readOnly, className, ...rest }, ref) {
  const f = useField();
  return (
    <input
      ref={ref}
      id={f?.id}
      aria-describedby={f?.describedBy}
      aria-invalid={f?.invalid || undefined}
      required={f?.required}
      readOnly={readOnly}
      className={cx(s.control, calculated && s.calculated, readOnly && s.readOnly, className)}
      {...rest}
    />
  );
});
```

`Select.tsx`:
```tsx
import { forwardRef, type SelectHTMLAttributes } from "react";
import { cx } from "@/lib/cx";
import { useField } from "../Field/FieldContext";
import s from "./Input.module.css";

export interface SelectOption { value: string; label: string }
export interface SelectProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, "style"> {
  options: SelectOption[];
  placeholder?: string;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select({ options, placeholder, className, ...rest }, ref) {
  const f = useField();
  return (
    <select ref={ref} id={f?.id} aria-describedby={f?.describedBy} aria-invalid={f?.invalid || undefined} required={f?.required} className={cx(s.control, className)} {...rest}>
      {placeholder && <option value="">{placeholder}</option>}
      {options.map((o) => (
        <option key={o.value} value={o.value}>{o.label}</option>
      ))}
    </select>
  );
});
```

`Checkbox.tsx` e `Radio.tsx` (mesmo padrão; Radio com `type="radio"`):
```tsx
import { forwardRef, type InputHTMLAttributes } from "react";
import s from "./Input.module.css";

interface CheckboxProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "style" | "type"> { label: string }

export const Checkbox = forwardRef<HTMLInputElement, CheckboxProps>(function Checkbox({ label, ...rest }, ref) {
  return (
    <label className={s.check}>
      <input ref={ref} type="checkbox" {...rest} />
      {label}
    </label>
  );
});
```

`DateInput.tsx`:
```tsx
import { forwardRef } from "react";
import { Input, type InputProps } from "./Input";

export const DateInput = forwardRef<HTMLInputElement, Omit<InputProps, "type">>(function DateInput(props, ref) {
  return <Input ref={ref} type="date" {...props} />;
});
```

- [ ] **Step 9: Teste do MoneyInput**

`MoneyInput.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { MoneyInput } from "./MoneyInput";

function Harness({ inicial = null as number | null }) {
  const [v, setV] = useState<number | null>(inicial);
  return (
    <>
      <MoneyInput aria-label="Valor" value={v} onChange={setV} />
      <output>{String(v)}</output>
    </>
  );
}

test("mostra formatado, edita cru, devolve número", async () => {
  const user = userEvent.setup();
  render(<Harness inicial={1234.5} />);
  const input = screen.getByLabelText("Valor");
  expect(input).toHaveValue("R$ 1.234,50");
  await user.click(input);
  expect(input).toHaveValue("1234,50");
  await user.clear(input);
  await user.type(input, "99,9");
  await user.tab();
  expect(input).toHaveValue("R$ 99,90");
  expect(screen.getByRole("status")).toHaveTextContent("99.9");
});

test("vazio devolve null", async () => {
  const user = userEvent.setup();
  render(<Harness inicial={10} />);
  const input = screen.getByLabelText("Valor");
  await user.click(input);
  await user.clear(input);
  await user.tab();
  expect(input).toHaveValue("");
  expect(screen.getByRole("status")).toHaveTextContent("null");
});
```

- [ ] **Step 10: MoneyInput e MoneyValue**

`MoneyInput.tsx`:
```tsx
import { forwardRef, useState, type FocusEvent, type InputHTMLAttributes } from "react";
import { cx } from "@/lib/cx";
import { formatarDinheiro, parsearDinheiro } from "@/lib/dinheiro";
import { useField } from "../Field/FieldContext";
import s from "./Input.module.css";

export interface MoneyInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "style" | "value" | "onChange" | "type"> {
  value: number | null;
  onChange: (valor: number | null) => void;
  calculated?: boolean;
  allowNegative?: boolean;
}

function cru(v: number | null) {
  return v === null ? "" : v.toFixed(2).replace(".", ",");
}

export const MoneyInput = forwardRef<HTMLInputElement, MoneyInputProps>(function MoneyInput(
  { value, onChange, calculated, allowNegative = false, readOnly, className, onFocus, onBlur, ...rest },
  ref,
) {
  const f = useField();
  const [editando, setEditando] = useState(false);
  const [texto, setTexto] = useState("");

  function focar(e: FocusEvent<HTMLInputElement>) {
    setTexto(cru(value));
    setEditando(true);
    requestAnimationFrame(() => e.target.select());
    onFocus?.(e);
  }
  function sair(e: FocusEvent<HTMLInputElement>) {
    let n = parsearDinheiro(texto);
    if (n !== null && !allowNegative && n < 0) n = Math.abs(n);
    onChange(n);
    setEditando(false);
    onBlur?.(e);
  }

  return (
    <div className={s.wrap}>
      <input
        ref={ref}
        id={f?.id}
        aria-describedby={f?.describedBy}
        aria-invalid={f?.invalid || undefined}
        inputMode="decimal"
        readOnly={readOnly}
        value={editando ? texto : formatarDinheiro(value)}
        onChange={(e) => setTexto(e.target.value)}
        onFocus={focar}
        onBlur={sair}
        className={cx(s.control, s.money, calculated && s.calculated, readOnly && s.readOnly, className)}
        {...rest}
      />
      {calculated && !editando && <span className={s.calcBadge} aria-hidden>calculado</span>}
    </div>
  );
});
```

`MoneyValue.tsx`:
```tsx
import { cx } from "@/lib/cx";
import { formatarDinheiro } from "@/lib/dinheiro";
import s from "./MoneyValue.module.css";

interface MoneyValueProps { value: number | null; emphasis?: "normal" | "result"; tone?: "normal" | "above" | "negative"; className?: string }

export function MoneyValue({ value, emphasis = "normal", tone, className }: MoneyValueProps) {
  const t = tone ?? (value !== null && value < 0 ? "negative" : "normal");
  return <span className={cx(s.value, emphasis === "result" && s.result, s[t], className)}>{formatarDinheiro(value) || "—"}</span>;
}
```

`MoneyValue.module.css`:
```css
.value { font-variant-numeric: tabular-nums; white-space: nowrap; }
.result { font: var(--type-section); color: var(--color-result-normal); }
.normal { color: inherit; }
.above { color: var(--color-result-above); }
.negative { color: var(--color-result-negative); }
```

(Adicionar `Create: frontend/src/components/Input/MoneyValue.module.css` à lista de arquivos.)

- [ ] **Step 11: Barrel**

`src/components/index.ts`:
```ts
export { Button, type ButtonProps, type ButtonVariant } from "./Button/Button";
export { IconButton } from "./Button/IconButton";
export { Field, type FieldProps } from "./Field/Field";
export { useField } from "./Field/FieldContext";
export { Input, type InputProps } from "./Input/Input";
export { Select, type SelectOption } from "./Input/Select";
export { Checkbox } from "./Input/Checkbox";
export { Radio } from "./Input/Radio";
export { DateInput } from "./Input/DateInput";
export { MoneyInput } from "./Input/MoneyInput";
export { MoneyValue } from "./Input/MoneyValue";
```

- [ ] **Step 12: Rodar**

Run: `cd frontend && npm run test && npm run lint && npm run typecheck`
Expected: todos os testes passam (fumaça + http + dinheiro + Button + Field + MoneyInput); lint e tokens verdes.

- [ ] **Step 13: Reportar arquivos tocados**

Commit sugerido: `feat(ui): form primitives — button, field, input, select, money input/value`

---

### Task 5: Chip, Badge, Tooltip, Alert e o mapa `apresentacaoStatus`

**Files:**
- Create: `frontend/src/dominio/status.ts`, `frontend/src/dominio/status.test.ts`
- Create: `frontend/src/components/Chip/Chip.tsx`, `Chip.module.css`, `Chip.test.tsx`
- Create: `frontend/src/components/Badge/Badge.tsx`, `Badge.module.css`, `StatusBadge.tsx`
- Create: `frontend/src/components/Tooltip/Tooltip.tsx`, `Tooltip.module.css`
- Create: `frontend/src/components/Alert/Alert.tsx`, `Alert.module.css`
- Create: `frontend/src/components/display.ts` (barrel desta task)

**Depends-on:** T01 (usa só `cx`, que T04 cria — se T05 rodar antes de T04 terminar, criar `src/lib/cx.ts` idêntico é colisão; **regra:** T05 importa `cx` de `@/lib/cx` e o controlador só despacha T05 na mesma onda de T04 porque T04 cria o arquivo no primeiro minuto; se preferir zero risco, mover T05 para a onda 2).

**Interfaces:**
- Produces:
  - `type Tone = "info" | "success" | "warning" | "danger" | "neutral"`
  - `apresentacaoStatus(entidade: "fase_viagem" | "comissao" | "reserva" | "repasse" | "despesa" | "pendencia" | "acesso", valor: string): { texto: string; tone: Tone }` — texto exato da spec §6.1; valor desconhecido → `{ texto: valor, tone: "neutral" }`.
  - `<Chip selected onClick>texto</Chip>` (selecionado mostra ✓, `aria-pressed`), `<Badge tone>texto</Badge>`, `<StatusBadge entidade valor />`, `<Tooltip text>{trigger}</Tooltip>` (só "como este valor é calculado"), `<Alert tone title? action?>children</Alert>`.

- [ ] **Step 1: Teste do mapa**

`src/dominio/status.test.ts`:
```ts
import { apresentacaoStatus } from "./status";

test("fases da viagem têm o texto da spec §6.1", () => {
  expect(apresentacaoStatus("fase_viagem", "sem_reserva")).toEqual({ texto: "Rascunho", tone: "neutral" });
  expect(apresentacaoStatus("fase_viagem", "em_emissao")).toEqual({ texto: "Em emissão", tone: "info" });
  expect(apresentacaoStatus("fase_viagem", "cancelada").tone).toBe("danger");
});

test("comissão atrasada é danger, recebida é success", () => {
  expect(apresentacaoStatus("comissao", "atrasada")).toEqual({ texto: "Atrasada", tone: "danger" });
  expect(apresentacaoStatus("comissao", "recebida").tone).toBe("success");
});

test("reserva pendente aparece como Em emissão", () => {
  expect(apresentacaoStatus("reserva", "pendente").texto).toBe("Em emissão");
});

test("repasse a_pagar é Liberado", () => {
  expect(apresentacaoStatus("repasse", "a_pagar")).toEqual({ texto: "Liberado", tone: "warning" });
});

test("valor desconhecido não quebra", () => {
  expect(apresentacaoStatus("reserva", "xyz")).toEqual({ texto: "xyz", tone: "neutral" });
});
```

- [ ] **Step 2: Rodar para ver falhar** — `npx vitest run src/dominio` → FAIL.

- [ ] **Step 3: `dominio/status.ts`**

```ts
export type Tone = "info" | "success" | "warning" | "danger" | "neutral";
export interface Apresentacao { texto: string; tone: Tone }

type Mapa = Record<string, Apresentacao>;

const fase_viagem: Mapa = {
  sem_reserva: { texto: "Rascunho", tone: "neutral" },
  em_emissao: { texto: "Em emissão", tone: "info" },
  confirmada: { texto: "Confirmada", tone: "info" },
  em_viagem: { texto: "Em viagem", tone: "info" },
  concluida: { texto: "Concluída", tone: "success" },
  cancelada: { texto: "Cancelada", tone: "danger" },
};
const comissao: Mapa = {
  nao_prevista: { texto: "Não prevista", tone: "neutral" },
  a_receber: { texto: "A receber", tone: "info" },
  parcial: { texto: "Parcial", tone: "warning" },
  atrasada: { texto: "Atrasada", tone: "danger" },
  recebida: { texto: "Recebida", tone: "success" },
  divergente: { texto: "Divergente", tone: "warning" },
};
const reserva: Mapa = {
  pendente: { texto: "Em emissão", tone: "info" },
  emitida: { texto: "Emitida", tone: "success" },
  cancelada: { texto: "Cancelada", tone: "danger" },
};
const repasse: Mapa = {
  bloqueado: { texto: "Bloqueado", tone: "neutral" },
  a_pagar: { texto: "Liberado", tone: "warning" },
  pago: { texto: "Pago", tone: "success" },
};
const despesa: Mapa = {
  a_pagar: { texto: "A pagar", tone: "info" },
  vencida: { texto: "Vencida", tone: "danger" },
  paga: { texto: "Paga", tone: "success" },
};
const pendencia: Mapa = {
  aberta: { texto: "Aberta", tone: "info" },
  urgente: { texto: "Urgente", tone: "danger" },
  atrasada: { texto: "Atrasada", tone: "danger" },
  concluida: { texto: "Concluída", tone: "success" },
  cancelada: { texto: "Cancelada", tone: "neutral" },
};
const acesso: Mapa = {
  acesso_ativo: { texto: "Acesso ativo", tone: "success" },
  sem_acesso: { texto: "Sem acesso", tone: "neutral" },
  convite_pendente: { texto: "Convite pendente", tone: "warning" },
  inativo: { texto: "Inativo", tone: "neutral" },
};

const mapas = { fase_viagem, comissao, reserva, repasse, despesa, pendencia, acesso } as const;
export type EntidadeStatus = keyof typeof mapas;

export function apresentacaoStatus(entidade: EntidadeStatus, valor: string): Apresentacao {
  return mapas[entidade][valor] ?? { texto: valor, tone: "neutral" };
}
```

- [ ] **Step 4: Teste do Chip**

`Chip.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { Chip } from "./Chip";

test("chip selecionado tem ✓ e aria-pressed", () => {
  render(<Chip selected onClick={() => undefined}>Aéreo</Chip>);
  const b = screen.getByRole("button", { name: /Aéreo/ });
  expect(b).toHaveAttribute("aria-pressed", "true");
  expect(b).toHaveTextContent("✓");
});
```

- [ ] **Step 5: Chip, Badge, StatusBadge, Tooltip, Alert**

`Chip.module.css`:
```css
.chip {
  display: inline-flex; align-items: center; gap: var(--space-1);
  height: var(--control-h-sm); padding: 0 var(--space-3);
  border: 1px solid var(--chip-off-border); border-radius: var(--radius-pill);
  background: transparent; color: var(--chip-off-text); font: var(--type-label); cursor: pointer;
}
.chip:hover { background: var(--color-bg-subtle); }
.on { background: var(--chip-on-bg); color: var(--chip-on-text); border-color: var(--chip-on-bg); }
```

`Chip.tsx`:
```tsx
import type { ButtonHTMLAttributes } from "react";
import { cx } from "@/lib/cx";
import s from "./Chip.module.css";

interface ChipProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "style"> { selected: boolean }

export function Chip({ selected, children, className, ...rest }: ChipProps) {
  return (
    <button type="button" aria-pressed={selected} className={cx(s.chip, selected && s.on, className)} {...rest}>
      {selected && <span aria-hidden>✓</span>}
      {children}
    </button>
  );
}
```

`Badge.module.css`:
```css
.badge {
  display: inline-flex; align-items: center; gap: var(--space-1);
  padding: 0 var(--space-2); height: 22px; border-radius: var(--radius-pill);
  font: var(--type-caption); letter-spacing: var(--tracking-caps); text-transform: uppercase; white-space: nowrap;
}
.info { background: var(--color-info-soft); color: var(--color-info-text); }
.success { background: var(--color-success-soft); color: var(--color-success-text); }
.warning { background: var(--color-warning-soft); color: var(--color-warning-text); }
.danger { background: var(--color-danger-soft); color: var(--color-danger-text); }
.neutral { background: var(--color-neutral-soft); color: var(--color-neutral-text); }
```

`Badge.tsx`:
```tsx
import type { ReactNode } from "react";
import type { Tone } from "@/dominio/status";
import { cx } from "@/lib/cx";
import s from "./Badge.module.css";

export function Badge({ tone, children, className }: { tone: Tone; children: ReactNode; className?: string }) {
  return <span className={cx(s.badge, s[tone], className)}>{children}</span>;
}
```

`StatusBadge.tsx`:
```tsx
import { apresentacaoStatus, type EntidadeStatus } from "@/dominio/status";
import { Badge } from "./Badge";

export function StatusBadge({ entidade, valor }: { entidade: EntidadeStatus; valor: string }) {
  const a = apresentacaoStatus(entidade, valor);
  return <Badge tone={a.tone}>{a.texto}</Badge>;
}
```

`Tooltip.tsx` (CSS puro, sem lib):
```tsx
import type { ReactNode } from "react";
import s from "./Tooltip.module.css";

export function Tooltip({ text, children }: { text: string; children: ReactNode }) {
  return (
    <span className={s.wrap} tabIndex={0} aria-label={text}>
      {children}
      <span role="tooltip" className={s.bubble}>{text}</span>
    </span>
  );
}
```

`Tooltip.module.css`:
```css
.wrap { position: relative; display: inline-flex; }
.bubble {
  position: absolute; bottom: calc(100% + var(--space-2)); left: 50%; transform: translateX(-50%);
  background: var(--toast-bg); color: var(--color-text-inverse); padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-md); font: var(--type-helper); white-space: nowrap; box-shadow: var(--shadow-float);
  visibility: hidden; opacity: 0; pointer-events: none; z-index: 20;
}
.wrap:hover .bubble, .wrap:focus-visible .bubble { visibility: visible; opacity: 1; }
```

`Alert.tsx`:
```tsx
import type { ReactNode } from "react";
import { AlertTriangle, CircleCheck, Info, OctagonAlert } from "lucide-react";
import type { Tone } from "@/dominio/status";
import { cx } from "@/lib/cx";
import s from "./Alert.module.css";

const icones = { info: Info, success: CircleCheck, warning: AlertTriangle, danger: OctagonAlert, neutral: Info };

export function Alert({ tone, title, action, children }: { tone: Tone; title?: string; action?: ReactNode; children: ReactNode }) {
  const Icone = icones[tone];
  return (
    <div role={tone === "danger" ? "alert" : "status"} className={cx(s.alert, s[tone])}>
      <Icone size={18} aria-hidden />
      <div className={s.body}>
        {title && <strong className={s.title}>{title}</strong>}
        <div>{children}</div>
      </div>
      {action}
    </div>
  );
}
```

`Alert.module.css`:
```css
.alert { display: flex; gap: var(--space-3); align-items: flex-start; padding: var(--space-3) var(--space-4); border-radius: var(--radius-lg); border: 1px solid transparent; font: var(--type-body); }
.body { flex: 1; display: flex; flex-direction: column; gap: var(--space-1); }
.title { font: var(--type-label); }
.info { background: var(--color-info-soft); color: var(--color-info-text); }
.success { background: var(--color-success-soft); color: var(--color-success-text); }
.warning { background: var(--color-warning-soft); color: var(--color-warning-text); }
.danger { background: var(--color-danger-soft); color: var(--color-danger-text); }
.neutral { background: var(--color-neutral-soft); color: var(--color-neutral-text); }
```

`src/components/display.ts`:
```ts
export { Chip } from "./Chip/Chip";
export { Badge } from "./Badge/Badge";
export { StatusBadge } from "./Badge/StatusBadge";
export { Tooltip } from "./Tooltip/Tooltip";
export { Alert } from "./Alert/Alert";
```

- [ ] **Step 6: Rodar** — `npm run test && npm run lint` → verde. (Badge usa `height: 22px` — permitido: o lint proíbe hex, font-size e @media; altura fixa de badge não está na lista. Não trocar por token novo: `tokens.css` está congelado.)

- [ ] **Step 7: Reportar arquivos tocados**

Commit sugerido: `feat(ui): chip, badge, status map, tooltip, alert`

---

### Task 6 (backend): `/auth/me` com permissões, `GET /auth/tokens/{token}`, `AddModules`, SPA estática, Dockerfile com Node

**Files:**
- Modify: `backend/src/Meridiano.Api/Auth/AuthEndpoints.cs` (MeResponse), `backend/src/Meridiano.Api/Auth/ConviteEndpoints.cs` (+ GET tokens), `backend/src/Meridiano.Api/Auth/ConviteService.cs` (+ `ConsultarTokenAsync`), `backend/src/Meridiano.Api/Auth/AuthExtensions.cs` (remover registro de `UsuarioService`), `backend/src/Meridiano.Api/Modules/Endpoints.cs` (+ `AddModules`), `backend/src/Meridiano.Api/Infra/InfraExtensions.cs` (static files + fallback), `backend/Dockerfile`, `backend/.dockerignore`, `backend/.gitignore` (+ `src/Meridiano.Api/wwwroot/`)
- Create: `backend/src/Meridiano.Data/Migrations/0012_localizar_usuario_por_token_dados.sql`
- Test: `backend/tests/Meridiano.Api.Tests/AuthTests.cs` (+1), `ConviteTests.cs` (+2), `InfraTests.cs` (+2)
- **Não tocar:** `Program.cs`. `AddModules` é chamado de dentro de `AddAuth`? Não — `Program.cs` não muda, então `AddModules(this WebApplicationBuilder)` é chamado por `AddSessao`? Também não. **Decisão:** `MapEndpoints` já é chamado no `Program.cs`; registrar os serviços de módulo em `Endpoints.MapEndpoints` não é possível (é pós-build). Solução sem tocar `Program.cs`: `AddAuth` chama `builder.AddModules()` na última linha, e `AddModules` (em `Modules/Endpoints.cs`) registra `UsuarioService` e, nas fases seguintes, os demais. A pendência "mover para fora de AddAuth" fica assim resolvida em espírito: um único ponto de registro por módulo, fora do arquivo de auth.

**Depends-on:** none (repo backend)

**Interfaces:**
- Produces:
  - `GET /api/v1/auth/me` → `{ usuarioId, agenciaId, perfil, nome, permissoes: string[] }` (chaves `viagem.ver`, …, `usuario.gerenciar`)
  - `GET /api/v1/auth/tokens/{token}` (anônimo, rate-limited pela política `login`) → `200 { nome, email, tipo: "convite" | "reset" }` ou `404` ProblemDetails `codigo: token_invalido`
  - `Endpoints.AddModules(this WebApplicationBuilder)` — ponto único de registro de serviços de módulo
  - API serve `wwwroot/` e devolve `index.html` para rotas que não começam com `/api` nem `/health`; `/api/v1/nao-existe` → 404 sem HTML
  - Dockerfile: estágio `node:24` builda `frontend/` (contexto = pasta pai, ver step 9) e copia `dist/` para `wwwroot/`

- [ ] **Step 1: Testes (falham antes)**

Em `AuthTests.cs`, trocar o record privado e acrescentar asserção:
```csharp
private sealed record MeResposta(Guid UsuarioId, Guid AgenciaId, string Perfil, string Nome, string[] Permissoes);
// no teste Login_correto_gera_cookie_e_me_retorna_claims, após Assert.Equal("dono", me.Perfil):
Assert.Contains("usuario.gerenciar", me.Permissoes);
Assert.Contains("viagem.criar", me.Permissoes);
```

Em `ConviteTests.cs`:
```csharp
[Fact]
public async Task Consultar_token_de_convite_devolve_nome_email_e_tipo()
{
    var agencia = await pg.InserirAgenciaAsync("Tok A");
    await pg.QueryOwnerAsync<int>(
        "insert into usuario (agencia_id, nome, email, perfil, convite_token, convite_expira_em) values (@agencia, 'Ana', 'ana@tok.com', 'agente', 'tok-abc', now() + interval '1 day') returning 1",
        new { agencia });

    await using var app = new MeridianoApiFactory(pg);
    var r = await app.CreateClient().GetAsync("/api/v1/auth/tokens/tok-abc");
    Assert.Equal(HttpStatusCode.OK, r.StatusCode);
    var corpo = await r.Content.ReadFromJsonAsync<TokenResposta>();
    Assert.Equal(("Ana", "ana@tok.com", "convite"), (corpo!.Nome, corpo.Email, corpo.Tipo));
}

[Fact]
public async Task Consultar_token_expirado_e_404_token_invalido()
{
    await using var app = new MeridianoApiFactory(pg);
    var r = await app.CreateClient().GetAsync("/api/v1/auth/tokens/nao-existe");
    Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);
    var pd = await r.Content.ReadFromJsonAsync<ProblemDetails>();
    Assert.Equal("token_invalido", pd!.Extensions["codigo"]!.ToString());
}

private sealed record TokenResposta(string Nome, string Email, string Tipo);
```
(`using Microsoft.AspNetCore.Mvc;` para `ProblemDetails`; conferir como `InfraTests` já lê `codigo` e copiar o mesmo padrão.)

Em `InfraTests.cs`:
```csharp
[Fact]
public async Task Rota_de_api_inexistente_e_404_sem_html()
{
    await using var app = new MeridianoApiFactory(pg);
    var r = await app.CreateClient().GetAsync("/api/v1/nao-existe");
    Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);
    Assert.DoesNotContain("text/html", r.Content.Headers.ContentType?.MediaType ?? "");
}

[Fact]
public async Task Rota_de_pagina_sem_wwwroot_e_404_sem_erro()
{
    await using var app = new MeridianoApiFactory(pg);
    var r = await app.CreateClient().GetAsync("/viagens/123");
    Assert.Equal(HttpStatusCode.NotFound, r.StatusCode);
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `cd backend && dotnet test --filter "FullyQualifiedName~AuthTests|FullyQualifiedName~ConviteTests|FullyQualifiedName~InfraTests"`
Expected: os 5 novos falham (compilação em Auth por `Permissoes` ausente no record; 404 em `/auth/tokens/…` já passa por acaso — o teste de 200 falha).

- [ ] **Step 3: Migration 0012 — função devolve nome, e-mail e tipo**

`0012_localizar_usuario_por_token_dados.sql`:
```sql
-- Tela "Definir senha"/"Redefinir senha" mostra nome e e-mail antes do login. Mesma função, mais colunas.
drop function if exists localizar_usuario_por_token(text);
create function localizar_usuario_por_token(p_token text)
returns table (id uuid, agencia_id uuid, nome text, email text, tipo text) as $$
  select u.id, u.agencia_id, u.nome, u.email,
         case when u.convite_token = p_token then 'convite' else 'reset' end
    from usuario u
   where u.ativo
     and ((u.convite_token = p_token and u.convite_expira_em > now())
       or (u.reset_token   = p_token and u.reset_expira_em   > now()))
   limit 1
$$ language sql stable security definer set search_path = pg_catalog, public;

revoke all on function localizar_usuario_por_token(text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'meridiano_api') then
    grant execute on function localizar_usuario_por_token(text) to meridiano_api;
  end if;
end $$;
```
(Conferir que o `.csproj` de `Meridiano.Data` embute `Migrations/*.sql` por glob — sim, desde a Fase 2.)

- [ ] **Step 4: `ConviteService.ConsultarTokenAsync` e endpoint**

Em `ConviteService.cs`:
```csharp
public sealed record TokenInfo(string Nome, string Email, string Tipo);

public async Task<TokenInfo?> ConsultarTokenAsync(string token, CancellationToken ct)
{
    await using var conexao = new NpgsqlConnection(config.GetConnectionString("Api")!);
    await conexao.OpenAsync(ct);
    return await conexao.QuerySingleOrDefaultAsync<TokenInfo>(
        "select nome, email, tipo from localizar_usuario_por_token(@token)", new { token });
}
```
`DefinirSenhaAsync` continua lendo só `id, agencia_id` (select explícito, não `*`).

Em `ConviteEndpoints.MapConviteEndpoints`, antes do `return app;`:
```csharp
g.MapGet("/tokens/{token}", async (string token, ConviteService convites, CancellationToken ct) =>
{
    var info = await convites.ConsultarTokenAsync(token, ct);
    return info is null
        ? Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Token inválido", detail: "Link inválido ou expirado", extensions: new Dictionary<string, object?> { ["codigo"] = "token_invalido" })
        : Results.Ok(info);
}).RequireRateLimiting(AuthExtensions.PoliticaLogin).AllowAnonymous();
```

- [ ] **Step 5: `/auth/me` com permissões**

Em `AuthEndpoints.cs`:
```csharp
public sealed record MeResponse(Guid UsuarioId, Guid AgenciaId, string Perfil, string Nome, IReadOnlyList<string> Permissoes);
// no MapGet("/me"):
return Results.Ok(new MeResponse(u.UsuarioId, u.AgenciaId, u.Perfil.ParaBanco(), u.Nome,
    Permissoes.Do(u.Perfil).Select(p => p.Chave()).Order().ToList()));
```

- [ ] **Step 6: `AddModules`**

`Modules/Endpoints.cs`:
```csharp
using Meridiano.Api.Auth;
using Meridiano.Api.Modules.Admin;

namespace Meridiano.Api.Modules;

public static class Endpoints
{
    // Ponto único de registro dos serviços de módulo. Chamado por AddAuth (Program.cs não muda).
    public static WebApplicationBuilder AddModules(this WebApplicationBuilder builder)
    {
        builder.Services.AddScoped<UsuarioService>();
        return builder;
    }

    public static WebApplication MapEndpoints(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1");
        api.MapAuthEndpoints();
        api.MapConviteEndpoints();
        api.MapAdminEndpoints();
        return app;
    }
}
```
Em `AuthExtensions.AddAuth`: remover `builder.Services.AddScoped<Meridiano.Api.Modules.Admin.UsuarioService>();` e, antes de `return builder;`, `builder.AddModules();` (com `using Meridiano.Api.Modules;`).

- [ ] **Step 7: SPA estática em `UseInfra`**

Em `InfraExtensions.UseInfra`, após `app.UseSerilogRequestLogging();`:
```csharp
app.UseDefaultFiles();
app.UseStaticFiles();
```
E após `app.MapHealthChecks("/health");`:
```csharp
// SPA: qualquer rota fora de /api e /health devolve index.html quando o build do front existe.
var indexHtml = Path.Combine(app.Environment.WebRootPath ?? "wwwroot", "index.html");
if (File.Exists(indexHtml))
{
    app.MapFallbackToFile("{*path:regex(^(?!api/|health).*$)}", "index.html");
}
```

- [ ] **Step 8: Rodar os testes**

Run: `cd backend && dotnet build -c Release && dotnet test`
Expected: 0 falhas; total 13 domínio + 31 API.

- [ ] **Step 9: Dockerfile com estágio Node e `.dockerignore`**

O front é outro repo, irmão de `backend/`. O build de imagem roda com contexto na **pasta pai** (`viva-erp/`): `docker build -f backend/Dockerfile -t meridiano .`. CI de deploy (Fase 4) clona os dois repos lado a lado.

`backend/Dockerfile`:
```dockerfile
FROM node:24-alpine AS web
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY backend/Directory.Build.props backend/Meridiano.sln ./
COPY backend/src/Meridiano.Domain/Meridiano.Domain.csproj src/Meridiano.Domain/
COPY backend/src/Meridiano.Data/Meridiano.Data.csproj src/Meridiano.Data/
COPY backend/src/Meridiano.Api/Meridiano.Api.csproj src/Meridiano.Api/
RUN dotnet restore src/Meridiano.Api/Meridiano.Api.csproj
COPY backend/src/ src/
COPY --from=web /web/dist src/Meridiano.Api/wwwroot
RUN dotnet publish src/Meridiano.Api/Meridiano.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
COPY --from=build /app .
USER app
ENTRYPOINT ["dotnet", "Meridiano.Api.dll"]
```

`backend/.dockerignore`:
```
**/bin
**/obj
**/node_modules
**/dist
**/.git
```
`backend/.gitignore`: acrescentar `src/Meridiano.Api/wwwroot/` (build local do front copia para lá; nunca commitar).

Verificar: `cd .. && docker build -f backend/Dockerfile -t meridiano .` termina sem erro (precisa de T01 concluída; se T06 rodar antes, deixar a verificação para o controlador na onda 1).

- [ ] **Step 10: Reportar arquivos tocados**

Commits sugeridos (repo `backend/`): `feat(auth): me returns permissoes; token lookup endpoint for invite/reset screens` · `feat(infra): serve SPA from wwwroot with api-safe fallback; node build stage in dockerfile` (controlador pode fazer um só).

---

### Task 7: Sessão, salvamento e atalhos — hooks sem UI

**Files:**
- Create: `frontend/src/lib/useSalvamento.ts`, `frontend/src/lib/useSalvamento.test.ts`, `frontend/src/lib/atalhos.ts`, `frontend/src/lib/atalhos.test.ts`, `frontend/src/lib/useAtalho.ts`

**Depends-on:** T01, T03 (tipos de erro)

**Interfaces:**
- Produces:
  - `useSalvamento<T>(salvar: (dados: T) => Promise<unknown>)` → `{ estado: "idle" | "dirty" | "saving" | "saved" | "error"; erro: unknown; marcarSujo(): void; executar(dados: T): Promise<boolean>; salvoEm: Date | null }` — `saved` volta a `idle` após 2 s (contrato: "✓ Salvo" por 2 s).
  - `registrarAtalho(combo: "ctrl+s" | "ctrl+enter" | "ctrl+k" | "escape", handler: () => void): () => void` (registry central; último registrado vence; devolve desregistro) · `useAtalho(combo, handler)` hook.

- [ ] **Step 1: Testes**

`useSalvamento.test.ts`:
```ts
import { act, renderHook } from "@testing-library/react";
import { useSalvamento } from "./useSalvamento";

test("idle → dirty → saving → saved → idle", async () => {
  vi.useFakeTimers();
  const salvar = vi.fn().mockResolvedValue(undefined);
  const { result } = renderHook(() => useSalvamento(salvar));
  expect(result.current.estado).toBe("idle");
  act(() => result.current.marcarSujo());
  expect(result.current.estado).toBe("dirty");
  let ok = false;
  await act(async () => { ok = await result.current.executar({ a: 1 }); });
  expect(ok).toBe(true);
  expect(result.current.estado).toBe("saved");
  expect(result.current.salvoEm).not.toBeNull();
  act(() => { vi.advanceTimersByTime(2000); });
  expect(result.current.estado).toBe("idle");
  vi.useRealTimers();
});

test("falha vai para error e mantém dirty ao marcar de novo", async () => {
  const salvar = vi.fn().mockRejectedValue(new Error("x"));
  const { result } = renderHook(() => useSalvamento(salvar));
  await act(async () => { await result.current.executar({}); });
  expect(result.current.estado).toBe("error");
  expect(result.current.erro).toBeInstanceOf(Error);
});
```

`atalhos.test.ts`:
```ts
import { registrarAtalho, tratarTecla } from "./atalhos";

test("ctrl+s chama o último registrado e previne default", () => {
  const a = vi.fn();
  const b = vi.fn();
  const solta = registrarAtalho("ctrl+s", a);
  registrarAtalho("ctrl+s", b);
  const ev = new KeyboardEvent("keydown", { key: "s", ctrlKey: true, cancelable: true });
  tratarTecla(ev);
  expect(b).toHaveBeenCalled();
  expect(a).not.toHaveBeenCalled();
  expect(ev.defaultPrevented).toBe(true);
  solta();
});

test("escape sem ctrl", () => {
  const h = vi.fn();
  registrarAtalho("escape", h);
  tratarTecla(new KeyboardEvent("keydown", { key: "Escape" }));
  expect(h).toHaveBeenCalled();
});
```

- [ ] **Step 2: Rodar para ver falhar** — `npx vitest run src/lib` → FAIL.

- [ ] **Step 3: Implementar**

`useSalvamento.ts`:
```ts
import { useCallback, useEffect, useRef, useState } from "react";

export type EstadoSalvamento = "idle" | "dirty" | "saving" | "saved" | "error";

export function useSalvamento<T>(salvar: (dados: T) => Promise<unknown>) {
  const [estado, setEstado] = useState<EstadoSalvamento>("idle");
  const [erro, setErro] = useState<unknown>(null);
  const [salvoEm, setSalvoEm] = useState<Date | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  const marcarSujo = useCallback(() => setEstado((e) => (e === "saving" ? e : "dirty")), []);

  const executar = useCallback(
    async (dados: T) => {
      setEstado("saving");
      setErro(null);
      try {
        await salvar(dados);
        setSalvoEm(new Date());
        setEstado("saved");
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setEstado((e) => (e === "saved" ? "idle" : e)), 2000);
        return true;
      } catch (e) {
        setErro(e);
        setEstado("error");
        return false;
      }
    },
    [salvar],
  );

  return { estado, erro, salvoEm, marcarSujo, executar };
}
```

`atalhos.ts`:
```ts
export type Combo = "ctrl+s" | "ctrl+enter" | "ctrl+k" | "escape";
type Handler = () => void;

const pilhas = new Map<Combo, Handler[]>();

export function registrarAtalho(combo: Combo, handler: Handler): () => void {
  const pilha = pilhas.get(combo) ?? [];
  pilha.push(handler);
  pilhas.set(combo, pilha);
  return () => {
    const i = pilha.lastIndexOf(handler);
    if (i >= 0) pilha.splice(i, 1);
  };
}

function comboDe(e: KeyboardEvent): Combo | null {
  const ctrl = e.ctrlKey || e.metaKey;
  if (ctrl && e.key.toLowerCase() === "s") return "ctrl+s";
  if (ctrl && e.key === "Enter") return "ctrl+enter";
  if (ctrl && e.key.toLowerCase() === "k") return "ctrl+k";
  if (!ctrl && e.key === "Escape") return "escape";
  return null;
}

export function tratarTecla(e: KeyboardEvent) {
  const combo = comboDe(e);
  if (!combo) return;
  const handler = pilhas.get(combo)?.at(-1);
  if (!handler) return;
  e.preventDefault();
  handler();
}

let instalado = false;
export function instalarAtalhos() {
  if (instalado || typeof window === "undefined") return;
  window.addEventListener("keydown", tratarTecla);
  instalado = true;
}
```

`useAtalho.ts`:
```ts
import { useEffect } from "react";
import { registrarAtalho, type Combo } from "./atalhos";

export function useAtalho(combo: Combo, handler: () => void) {
  useEffect(() => registrarAtalho(combo, handler), [combo, handler]);
}
```

- [ ] **Step 4: Rodar** — `npm run test && npm run lint` → verde.

- [ ] **Step 5: Reportar arquivos tocados**

Commit sugerido: `feat(lib): save state machine hook and central shortcut registry`

---

### Task 8: Feedback — Toast, Modal, Skeleton, EmptyState

**Files:**
- Create: `frontend/src/components/Toast/toast.ts`, `ToastHost.tsx`, `Toast.module.css`, `toast.test.tsx`
- Create: `frontend/src/components/Modal/Modal.tsx`, `Modal.module.css`, `Modal.test.tsx`, `ConfirmModal.tsx`
- Create: `frontend/src/components/Skeleton/Skeleton.tsx`, `Skeleton.module.css`
- Create: `frontend/src/components/EmptyState/EmptyState.tsx`, `EmptyState.module.css`
- Create: `frontend/src/components/feedback.ts` (barrel)

**Depends-on:** T04 (Button), T07 (`useAtalho` para Esc)

**Interfaces:**
- Produces:
  - `toast.success(texto)` · `toast.error(texto)` · `toast.undo(texto, desfazer: () => void)` — API restrita (contrato). `<ToastHost />` montado uma vez no `App`. Toast some em 5 s; `undo` em 8 s. `aria-live="polite"`.
  - `<Modal open title onClose size?="md"|"lg" footer?>children</Modal>` — `role="dialog"` `aria-modal`, focus trap, `Esc` fecha via registry, foco volta ao disparador.
  - `<ConfirmModal open title impact confirmLabel tone="danger"|"primary" onConfirm onCancel loading? />` — botão de cancelar é a opção segura (foco inicial).
  - `<Skeleton lines?=3 />`, `<Skeleton.Block height="control"|"card"|"table" />` — só aparece após 300 ms (`useAtraso(300)` interno).
  - `<EmptyState title description action?: ReactNode icon?: ReactNode />`.

- [ ] **Step 1: Testes**

`toast.test.tsx`:
```tsx
import { act, render, screen } from "@testing-library/react";
import { ToastHost } from "./ToastHost";
import { toast } from "./toast";

test("toast.success aparece e some", () => {
  vi.useFakeTimers();
  render(<ToastHost />);
  act(() => toast.success("Viagem salva"));
  expect(screen.getByRole("status")).toHaveTextContent("Viagem salva");
  act(() => { vi.advanceTimersByTime(5000); });
  expect(screen.queryByText("Viagem salva")).toBeNull();
  vi.useRealTimers();
});

test("toast.undo chama desfazer", () => {
  const desfazer = vi.fn();
  render(<ToastHost />);
  act(() => toast.undo("Reserva cancelada", desfazer));
  screen.getByRole("button", { name: "Desfazer" }).click();
  expect(desfazer).toHaveBeenCalled();
});
```

`Modal.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Modal } from "./Modal";

test("dialog acessível, fecha com Esc", async () => {
  const onClose = vi.fn();
  render(<Modal open title="Sair sem salvar?" onClose={onClose}>corpo</Modal>);
  const d = screen.getByRole("dialog", { name: "Sair sem salvar?" });
  expect(d).toHaveAttribute("aria-modal", "true");
  await userEvent.keyboard("{Escape}");
  expect(onClose).toHaveBeenCalled();
});

test("fechado não renderiza", () => {
  render(<Modal open={false} title="x" onClose={() => undefined}>corpo</Modal>);
  expect(screen.queryByRole("dialog")).toBeNull();
});
```
(Instalar o registry no teste: `Modal` chama `instalarAtalhos()` no mount.)

- [ ] **Step 2: Rodar para ver falhar** — FAIL.

- [ ] **Step 3: Toast**

`toast.ts`:
```ts
import { useSyncExternalStore } from "react";

export interface ToastItem { id: number; tipo: "success" | "error" | "undo"; texto: string; desfazer?: () => void }

let itens: ToastItem[] = [];
let seq = 0;
const ouvintes = new Set<() => void>();
const notificar = () => ouvintes.forEach((o) => o());

function adicionar(item: Omit<ToastItem, "id">, ms: number) {
  const id = ++seq;
  itens = [...itens, { ...item, id }];
  notificar();
  setTimeout(() => remover(id), ms);
}
export function remover(id: number) {
  itens = itens.filter((t) => t.id !== id);
  notificar();
}

export const toast = {
  success: (texto: string) => adicionar({ tipo: "success", texto }, 5000),
  error: (texto: string) => adicionar({ tipo: "error", texto }, 5000),
  undo: (texto: string, desfazer: () => void) => adicionar({ tipo: "undo", texto, desfazer }, 8000),
};

export function useToasts() {
  return useSyncExternalStore(
    (cb) => { ouvintes.add(cb); return () => ouvintes.delete(cb); },
    () => itens,
  );
}
```

`ToastHost.tsx`:
```tsx
import { X } from "lucide-react";
import { IconButton } from "@/components";
import { cx } from "@/lib/cx";
import { remover, useToasts } from "./toast";
import s from "./Toast.module.css";

export function ToastHost() {
  const itens = useToasts();
  return (
    <div className={s.host} aria-live="polite">
      {itens.map((t) => (
        <div key={t.id} role="status" className={cx(s.toast, s[t.tipo])}>
          <span>{t.texto}</span>
          {t.tipo === "undo" && t.desfazer && (
            <button type="button" className={s.link} onClick={() => { t.desfazer?.(); remover(t.id); }}>Desfazer</button>
          )}
          <IconButton label="Fechar" icon={<X size={16} />} onClick={() => remover(t.id)} className={s.close} />
        </div>
      ))}
    </div>
  );
}
```

`Toast.module.css`:
```css
.host { position: fixed; bottom: var(--space-6); right: var(--space-6); display: flex; flex-direction: column; gap: var(--space-2); z-index: 60; }
.toast { display: flex; align-items: center; gap: var(--space-3); min-width: 280px; max-width: 420px; padding: var(--space-3) var(--space-4); border-radius: var(--radius-lg); background: var(--toast-bg); color: var(--color-text-inverse); font: var(--type-body); box-shadow: var(--shadow-float); }
.error { background: var(--color-danger); }
.link { background: none; border: 0; color: var(--toast-link); font: var(--type-label); cursor: pointer; padding: 0; }
.close { color: inherit; margin-left: auto; }
```

- [ ] **Step 4: Modal e ConfirmModal**

`Modal.tsx`:
```tsx
import { useEffect, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { IconButton } from "@/components";
import { instalarAtalhos } from "@/lib/atalhos";
import { useAtalho } from "@/lib/useAtalho";
import { cx } from "@/lib/cx";
import s from "./Modal.module.css";

export interface ModalProps { open: boolean; title: string; onClose: () => void; size?: "md" | "lg"; footer?: ReactNode; children: ReactNode }

const FOCAVEIS = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

export function Modal({ open, title, onClose, size = "md", footer, children }: ModalProps) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(instalarAtalhos, []);
  useAtalho("escape", open ? onClose : () => undefined);

  useEffect(() => {
    if (!open) return;
    const anterior = document.activeElement as HTMLElement | null;
    const el = ref.current;
    const focaveis = el?.querySelectorAll<HTMLElement>(FOCAVEIS);
    (focaveis?.[0] ?? el)?.focus();
    function prender(e: KeyboardEvent) {
      if (e.key !== "Tab" || !focaveis?.length) return;
      const primeiro = focaveis[0]!;
      const ultimo = focaveis[focaveis.length - 1]!;
      if (e.shiftKey && document.activeElement === primeiro) { e.preventDefault(); ultimo.focus(); }
      else if (!e.shiftKey && document.activeElement === ultimo) { e.preventDefault(); primeiro.focus(); }
    }
    el?.addEventListener("keydown", prender);
    return () => { el?.removeEventListener("keydown", prender); anterior?.focus(); };
  }, [open]);

  if (!open) return null;
  return createPortal(
    <div className={s.backdrop} onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div ref={ref} role="dialog" aria-modal="true" aria-labelledby="modal-title" tabIndex={-1} className={cx(s.modal, size === "lg" && s.lg)}>
        <header className={s.header}>
          <h2 id="modal-title" className={s.title}>{title}</h2>
          <IconButton label="Fechar" icon={<X size={20} />} onClick={onClose} />
        </header>
        <div className={s.body}>{children}</div>
        {footer && <footer className={s.footer}>{footer}</footer>}
      </div>
    </div>,
    document.body,
  );
}
```

`Modal.module.css`:
```css
.backdrop { position: fixed; inset: 0; background: rgb(41 35 92 / 0.45); display: grid; place-items: center; z-index: 50; padding: var(--space-4); }
.modal { width: min(480px, 100%); background: var(--color-bg-surface); border-radius: var(--radius-lg); box-shadow: var(--shadow-modal); display: flex; flex-direction: column; max-height: 90vh; }
.lg { width: min(720px, 100%); }
.header { display: flex; align-items: center; justify-content: space-between; padding: var(--space-4) var(--space-6); border-bottom: 1px solid var(--color-border); }
.title { font: var(--type-section); color: var(--color-text-heading); }
.body { padding: var(--space-6); overflow: auto; font: var(--type-body); }
.footer { display: flex; justify-content: flex-end; gap: var(--space-2); padding: var(--space-4) var(--space-6); border-top: 1px solid var(--color-border); }
```
(`rgb(41 35 92 / 0.45)` é o navy com alfa; não é hex e não existe token de backdrop — aceito e documentado aqui. Não criar token: `tokens.css` está congelado.)

`ConfirmModal.tsx`:
```tsx
import { Button } from "@/components";
import { Modal } from "./Modal";

interface ConfirmModalProps { open: boolean; title: string; impact: string; confirmLabel: string; tone?: "danger" | "primary"; loading?: boolean; onConfirm: () => void; onCancel: () => void }

export function ConfirmModal({ open, title, impact, confirmLabel, tone = "primary", loading, onConfirm, onCancel }: ConfirmModalProps) {
  return (
    <Modal
      open={open}
      title={title}
      onClose={onCancel}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel} autoFocus>Cancelar</Button>
          <Button variant={tone} onClick={onConfirm} loading={loading}>{confirmLabel}</Button>
        </>
      }
    >
      {impact}
    </Modal>
  );
}
```

- [ ] **Step 5: Skeleton e EmptyState**

`Skeleton.tsx`:
```tsx
import { useEffect, useState } from "react";
import { cx } from "@/lib/cx";
import s from "./Skeleton.module.css";

function useAtraso(ms: number) {
  const [mostrar, setMostrar] = useState(false);
  useEffect(() => { const t = setTimeout(() => setMostrar(true), ms); return () => clearTimeout(t); }, [ms]);
  return mostrar;
}

export function Skeleton({ lines = 3 }: { lines?: number }) {
  if (!useAtraso(300)) return null;
  return (
    <div className={s.group} aria-busy="true" aria-label="Carregando">
      {Array.from({ length: lines }, (_, i) => <div key={i} className={cx(s.line, i === lines - 1 && s.short)} />)}
    </div>
  );
}

Skeleton.Block = function Block({ height }: { height: "control" | "card" | "table" }) {
  if (!useAtraso(300)) return null;
  return <div className={cx(s.line, s[height])} aria-busy="true" />;
};
```

`Skeleton.module.css`:
```css
.group { display: flex; flex-direction: column; gap: var(--space-2); }
.line { height: var(--space-4); border-radius: var(--radius-sm); background: linear-gradient(90deg, var(--color-bg-subtle), var(--color-border), var(--color-bg-subtle)); background-size: 200% 100%; animation: brilho 1.2s linear infinite; }
.short { width: 60%; }
.control { height: var(--control-h); }
.card { height: 120px; border-radius: var(--card-radius); }
.table { height: 240px; border-radius: var(--card-radius); }
@keyframes brilho { from { background-position: 200% 0; } to { background-position: -200% 0; } }
```

`EmptyState.tsx`:
```tsx
import type { ReactNode } from "react";
import s from "./EmptyState.module.css";

export function EmptyState({ title, description, action, icon }: { title: string; description: string; action?: ReactNode; icon?: ReactNode }) {
  return (
    <div className={s.empty}>
      {icon && <div className={s.icon}>{icon}</div>}
      <h3 className={s.title}>{title}</h3>
      <p className={s.desc}>{description}</p>
      {action}
    </div>
  );
}
```

`EmptyState.module.css`:
```css
.empty { display: flex; flex-direction: column; align-items: center; gap: var(--space-2); padding: var(--space-12) var(--space-6); text-align: center; color: var(--color-text-secondary); }
.icon { color: var(--color-text-muted); }
.title { font: var(--type-component); color: var(--color-text-heading); }
.desc { font: var(--type-body); max-width: 420px; }
```

`feedback.ts`:
```ts
export { toast } from "./Toast/toast";
export { ToastHost } from "./Toast/ToastHost";
export { Modal, type ModalProps } from "./Modal/Modal";
export { ConfirmModal } from "./Modal/ConfirmModal";
export { Skeleton } from "./Skeleton/Skeleton";
export { EmptyState } from "./EmptyState/EmptyState";
```

- [ ] **Step 6: Rodar** — `npm run test && npm run lint` → verde.

- [ ] **Step 7: Reportar arquivos tocados**

Commit sugerido: `feat(ui): toast, modal with focus trap, skeleton, empty state`

---

### Task 9: Autenticação no front — AuthProvider, guarda de rota, telas Login / Definir senha / Esqueci senha / Redefinir senha, router

**Files:**
- Create: `frontend/src/auth/tipos.ts`, `frontend/src/auth/AuthProvider.tsx`, `frontend/src/auth/useAuth.ts`, `frontend/src/auth/RequireAuth.tsx`, `frontend/src/auth/AuthProvider.test.tsx`
- Create: `frontend/src/pages/acesso/AuthLayout.tsx`, `AuthLayout.module.css`, `LoginPage.tsx`, `LoginPage.test.tsx`, `DefinirSenhaPage.tsx`, `EsqueciSenhaPage.tsx`, `RedefinirSenhaPage.tsx`, `SenhaForm.tsx`, `SenhaForm.test.tsx`
- Create: `frontend/src/router.tsx`
- Modify: `frontend/src/App.tsx`, `frontend/src/App.test.tsx`

**Depends-on:** T03, T04, T05, T06 (contrato), T08

**Interfaces:**
- Consumes: `api`, erros (T03); `Button Field Input` (T04); `Alert` (T05); `toast` (T08); `GET /auth/me`, `POST /auth/login`, `POST /auth/logout`, `GET /auth/tokens/{token}`, `POST /auth/definir-senha`, `POST /auth/esqueci-senha` (T06).
- Produces:
  - `interface Me { usuarioId: string; agenciaId: string; perfil: string; nome: string; permissoes: string[] }`
  - `useAuth()` → `{ me: Me | null; carregando: boolean; pode(permissao: string): boolean; entrar(email, senha): Promise<void>; sair(): Promise<void>; recarregar(): Promise<void> }`
  - `<RequireAuth />` (Outlet; redireciona para `/login?voltar=<path>` sem sessão)
  - Rotas: `/login` `/definir-senha?token=` `/esqueci-senha` `/redefinir-senha?token=` e `/` (protegida; T10 preenche o shell). `router.tsx` exporta `<AppRoutes />`; T10 acrescenta rotas **em `src/shell/rotasModulos.tsx`** e `router.tsx` já as importa (arquivo criado aqui com placeholder que T10 substitui — ver Files de T10).

- [ ] **Step 1: Testes**

`AuthProvider.test.tsx`:
```tsx
import { render, screen, waitFor } from "@testing-library/react";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "@/api/queryClient";
import { AuthProvider } from "./AuthProvider";
import { useAuth } from "./useAuth";

function Quem() {
  const { me, carregando, pode } = useAuth();
  if (carregando) return <p>carregando</p>;
  return <p>{me ? `${me.nome}:${String(pode("viagem.criar"))}` : "anônimo"}</p>;
}

beforeEach(() => { vi.restoreAllMocks(); queryClient.clear(); });

test("carrega /auth/me e expõe pode()", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({ usuarioId: "1", agenciaId: "2", perfil: "dono", nome: "Gui", permissoes: ["viagem.criar"] }), { status: 200, headers: { "content-type": "application/json" } }));
  render(<QueryClientProvider client={queryClient}><AuthProvider><Quem /></AuthProvider></QueryClientProvider>);
  await waitFor(() => expect(screen.getByText("Gui:true")).toBeInTheDocument());
});

test("401 vira anônimo sem erro", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 401 }));
  render(<QueryClientProvider client={queryClient}><AuthProvider><Quem /></AuthProvider></QueryClientProvider>);
  await waitFor(() => expect(screen.getByText("anônimo")).toBeInTheDocument());
});
```

`LoginPage.test.tsx`:
```tsx
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "@/api/queryClient";
import { AuthProvider } from "@/auth/AuthProvider";
import { LoginPage } from "./LoginPage";

function montar() {
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter><AuthProvider><LoginPage /></AuthProvider></MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => { vi.restoreAllMocks(); queryClient.clear(); });

test("senha errada mostra o texto do protótipo", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    if (String(url).endsWith("/auth/me")) return new Response(null, { status: 401 });
    return new Response(null, { status: 401 });
  });
  montar();
  const user = userEvent.setup();
  await user.type(await screen.findByLabelText(/E-mail/), "a@b.com");
  await user.type(screen.getByLabelText(/Senha/), "errada");
  await user.click(screen.getByRole("button", { name: "Entrar" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("E-mail ou senha incorretos."));
});
```

`SenhaForm.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SenhaForm } from "./SenhaForm";

test("valida 8 caracteres, diferente do e-mail e confirmação", async () => {
  const onSubmit = vi.fn();
  render(<SenhaForm email="ana@x.com" submitLabel="Definir senha e entrar" onSubmit={onSubmit} />);
  const user = userEvent.setup();
  await user.type(screen.getByLabelText(/Nova senha/), "ana@x.com");
  await user.type(screen.getByLabelText(/Confirmar senha/), "outra");
  await user.click(screen.getByRole("button", { name: "Definir senha e entrar" }));
  expect(onSubmit).not.toHaveBeenCalled();
  expect(screen.getAllByRole("alert").length).toBeGreaterThan(0);
});
```

- [ ] **Step 2: Rodar para ver falhar** — FAIL.

- [ ] **Step 3: `auth/tipos.ts`, `AuthProvider.tsx`, `useAuth.ts`, `RequireAuth.tsx`**

`tipos.ts`:
```ts
export interface Me { usuarioId: string; agenciaId: string; perfil: string; nome: string; permissoes: string[] }
```

`AuthProvider.tsx`:
```tsx
import { createContext, useCallback, useMemo, type ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/api/http";
import { UnauthenticatedError } from "@/api/errors";
import type { Me } from "./tipos";

export interface AuthValue {
  me: Me | null;
  carregando: boolean;
  pode: (permissao: string) => boolean;
  entrar: (email: string, senha: string) => Promise<void>;
  sair: () => Promise<void>;
  recarregar: () => Promise<void>;
}

export const AuthContext = createContext<AuthValue | null>(null);
export const CHAVE_ME = ["auth", "me"] as const;

async function buscarMe(): Promise<Me | null> {
  try {
    return await api.get<Me>("/auth/me");
  } catch (e) {
    if (e instanceof UnauthenticatedError) return null;
    throw e;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const { data, isPending } = useQuery({ queryKey: CHAVE_ME, queryFn: buscarMe, staleTime: Infinity, retry: false, throwOnError: false });
  const me = data ?? null;

  const recarregar = useCallback(async () => { await qc.invalidateQueries({ queryKey: CHAVE_ME }); }, [qc]);
  const entrar = useCallback(async (email: string, senha: string) => {
    await api.post("/auth/login", { email, senha });
    await recarregar();
  }, [recarregar]);
  const sair = useCallback(async () => {
    await api.post("/auth/logout");
    qc.setQueryData(CHAVE_ME, null);
    qc.clear();
  }, [qc]);

  const value = useMemo<AuthValue>(() => ({
    me, carregando: isPending, recarregar, entrar, sair,
    pode: (p) => me?.permissoes.includes(p) ?? false,
  }), [me, isPending, recarregar, entrar, sair]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

`useAuth.ts`:
```ts
import { useContext } from "react";
import { AuthContext } from "./AuthProvider";

export function useAuth() {
  const v = useContext(AuthContext);
  if (!v) throw new Error("useAuth fora de AuthProvider");
  return v;
}
```

`RequireAuth.tsx`:
```tsx
import { Navigate, Outlet, useLocation } from "react-router";
import { useAuth } from "./useAuth";

export function RequireAuth() {
  const { me, carregando } = useAuth();
  const loc = useLocation();
  if (carregando) return null;
  if (!me) return <Navigate to={`/login?voltar=${encodeURIComponent(loc.pathname + loc.search)}`} replace />;
  return <Outlet />;
}
```

- [ ] **Step 4: Layout e telas de acesso**

`AuthLayout.tsx` (duas colunas: arte navy à esquerda com o texto do protótipo, formulário à direita; abaixo de 1024 vira uma coluna):
```tsx
import type { ReactNode } from "react";
import s from "./AuthLayout.module.css";

export function AuthLayout({ subtitle, children }: { subtitle: string; children: ReactNode }) {
  return (
    <div className={s.auth}>
      <aside className={s.art}>
        <div className={s.brand}>Meridiano</div>
        <p className={s.lead}>{subtitle}</p>
        <p className={s.copy}>© 2026 Build Solutions</p>
      </aside>
      <main className={s.panel}>{children}</main>
    </div>
  );
}
```

`AuthLayout.module.css`:
```css
.auth { min-height: 100vh; display: grid; grid-template-columns: 1fr 1fr; }
.art { background: var(--color-brand); color: var(--color-text-inverse); padding: var(--space-12); display: flex; flex-direction: column; gap: var(--space-6); }
.brand { font: var(--type-display); }
.lead { font: var(--type-section); color: var(--color-text-on-dark-muted); max-width: 420px; }
.copy { margin-top: auto; font: var(--type-helper); opacity: 0.7; }
.panel { display: grid; place-items: center; padding: var(--space-8); }
.form { width: min(400px, 100%); display: flex; flex-direction: column; gap: var(--space-4); }
.title { font: var(--type-page); color: var(--color-text-heading); margin-bottom: var(--space-2); }
.links { display: flex; justify-content: space-between; font: var(--type-label); }
@media (max-width: 1024px) { .auth { grid-template-columns: 1fr; } .art { padding: var(--space-6); } }
```
`LoginPage.tsx`:
```tsx
import { useState, type FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { Button, Field, Input } from "@/components";
import { Alert } from "@/components/display";
import { UnauthenticatedError } from "@/api/errors";
import { mensagemDeErro } from "@/api/http";
import { useAuth } from "@/auth/useAuth";
import { AuthLayout } from "./AuthLayout";
import s from "./AuthLayout.module.css";

export function LoginPage() {
  const { entrar } = useAuth();
  const nav = useNavigate();
  const [params] = useSearchParams();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function submeter(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setEnviando(true);
    try {
      await entrar(email.trim(), senha);
      nav(params.get("voltar") ?? "/", { replace: true });
    } catch (ex) {
      setErro(ex instanceof UnauthenticatedError ? "E-mail ou senha incorretos." : mensagemDeErro(ex));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <AuthLayout subtitle="Vendas, comissões e operação da agência num só lugar. Lance a viagem em minutos, saiba quanto cada reserva deixa e nunca esqueça uma comissão atrasada.">
      <form className={s.form} onSubmit={submeter} noValidate>
        <h1 className={s.title}>Entrar</h1>
        {erro && <Alert tone="danger">{erro}</Alert>}
        <Field label="E-mail" required>
          <Input type="email" autoComplete="username" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} />
        </Field>
        <Field label="Senha" required>
          <Input type="password" autoComplete="current-password" value={senha} onChange={(e) => setSenha(e.target.value)} />
        </Field>
        <Button variant="primary" type="submit" loading={enviando}>Entrar</Button>
        <div className={s.links}><Link to="/esqueci-senha">Esqueci minha senha</Link></div>
      </form>
    </AuthLayout>
  );
}
```

`SenhaForm.tsx` (compartilhado por Definir e Redefinir; usa react-hook-form):
```tsx
import { useForm } from "react-hook-form";
import { Button, Field, Input } from "@/components";
import s from "./AuthLayout.module.css";

interface Valores { senha: string; confirmar: string }

export function SenhaForm({ email, submitLabel, onSubmit, enviando }: { email: string; submitLabel: string; onSubmit: (senha: string) => void; enviando?: boolean }) {
  const { register, handleSubmit, watch, formState: { errors } } = useForm<Valores>({ mode: "onSubmit" });
  const senha = watch("senha", "");
  return (
    <form className={s.form} onSubmit={handleSubmit((v) => onSubmit(v.senha))} noValidate>
      <Field label="Nova senha" required helper="✓ Pelo menos 8 caracteres · ✓ Diferente do e-mail" error={errors.senha?.message}>
        <Input
          type="password"
          autoComplete="new-password"
          autoFocus
          {...register("senha", {
            required: "Informe a senha",
            minLength: { value: 8, message: "Pelo menos 8 caracteres" },
            validate: (v) => v.toLowerCase() !== email.toLowerCase() || "A senha não pode ser igual ao e-mail",
          })}
        />
      </Field>
      <Field label="Confirmar senha" required error={errors.confirmar?.message}>
        <Input type="password" autoComplete="new-password" {...register("confirmar", { validate: (v) => v === senha || "As senhas não conferem" })} />
      </Field>
      <Button variant="primary" type="submit" loading={enviando}>{submitLabel}</Button>
    </form>
  );
}
```

`DefinirSenhaPage.tsx` e `RedefinirSenhaPage.tsx` compartilham a lógica; a diferença é o subtítulo, o título e o rótulo. Implementar um componente interno `TokenPage` em `DefinirSenhaPage.tsx` e exportar os dois:
```tsx
import { useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { useQuery } from "@tanstack/react-query";
import { api, mensagemDeErro } from "@/api/http";
import { Field, Input } from "@/components";
import { Alert } from "@/components/display";
import { Skeleton } from "@/components/feedback";
import { useAuth } from "@/auth/useAuth";
import { AuthLayout } from "./AuthLayout";
import { SenhaForm } from "./SenhaForm";
import s from "./AuthLayout.module.css";

interface TokenInfo { nome: string; email: string; tipo: "convite" | "reset" }

function TokenPage({ subtitle, title, submitLabel }: { subtitle: string; title: string; submitLabel: string }) {
  const [params] = useSearchParams();
  const token = params.get("token") ?? "";
  const nav = useNavigate();
  const { entrar } = useAuth();
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const info = useQuery({ queryKey: ["auth", "token", token], queryFn: () => api.get<TokenInfo>(`/auth/tokens/${encodeURIComponent(token)}`), enabled: token !== "", retry: false });

  async function definir(senha: string) {
    setEnviando(true);
    setErro(null);
    try {
      await api.post("/auth/definir-senha", { token, senha });
      await entrar(info.data!.email, senha);
      nav("/", { replace: true });
    } catch (e) {
      setErro(mensagemDeErro(e));
    } finally {
      setEnviando(false);
    }
  }

  return (
    <AuthLayout subtitle={subtitle}>
      <div className={s.form}>
        <h1 className={s.title}>{title}</h1>
        {info.isPending && token && <Skeleton lines={4} />}
        {(info.isError || !token) && (
          <Alert tone="danger">Link inválido ou expirado. Peça um novo em <Link to="/esqueci-senha">"Esqueci minha senha"</Link>.</Alert>
        )}
        {info.data && (
          <>
            <Field label="Nome"><Input readOnly value={info.data.nome} /></Field>
            <Field label="E-mail"><Input readOnly value={info.data.email} /></Field>
            {erro && <Alert tone="danger">{erro}</Alert>}
            <SenhaForm email={info.data.email} submitLabel={submitLabel} onSubmit={definir} enviando={enviando} />
          </>
        )}
      </div>
    </AuthLayout>
  );
}

export const DefinirSenhaPage = () => (
  <TokenPage subtitle="Você foi convidada para a agência. Defina sua senha para começar. O convite vale por 72 horas." title="Definir senha" submitLabel="Definir senha e entrar" />
);
export const RedefinirSenhaPage = () => (
  <TokenPage subtitle="Defina uma nova senha. Link válido por 2 horas e de uso único." title="Redefinir senha" submitLabel="Salvar nova senha e entrar" />
);
```
(`RedefinirSenhaPage.tsx` vira `export { RedefinirSenhaPage } from "./DefinirSenhaPage";` para manter o arquivo listado.)

`EsqueciSenhaPage.tsx`:
```tsx
import { useState, type FormEvent } from "react";
import { Link } from "react-router";
import { api, mensagemDeErro } from "@/api/http";
import { Button, Field, Input } from "@/components";
import { Alert } from "@/components/display";
import { AuthLayout } from "./AuthLayout";
import s from "./AuthLayout.module.css";

export function EsqueciSenhaPage() {
  const [email, setEmail] = useState("");
  const [estado, setEstado] = useState<"idle" | "enviando" | "enviado" | "erro">("idle");
  const [erro, setErro] = useState("");

  async function submeter(e: FormEvent) {
    e.preventDefault();
    setEstado("enviando");
    try {
      await api.post("/auth/esqueci-senha", { email: email.trim() });
      setEstado("enviado");
    } catch (ex) {
      setErro(mensagemDeErro(ex));
      setEstado("erro");
    }
  }

  return (
    <AuthLayout subtitle="Recuperar acesso. Receba um link para redefinir sua senha no e-mail cadastrado. Ele vale por 2 horas.">
      <form className={s.form} onSubmit={submeter} noValidate>
        <h1 className={s.title}>Esqueci minha senha</h1>
        {estado === "enviado" && <Alert tone="success">Se o e-mail existir, você recebe o link em instantes. Não revelamos se um e-mail está cadastrado.</Alert>}
        {estado === "erro" && <Alert tone="danger">{erro}</Alert>}
        <Field label="E-mail" required>
          <Input type="email" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} />
        </Field>
        <Button variant="primary" type="submit" loading={estado === "enviando"}>Enviar link de redefinição</Button>
        <div className={s.links}><Link to="/login">Voltar ao login</Link></div>
      </form>
    </AuthLayout>
  );
}
```

- [ ] **Step 5: Router e App**

`router.tsx`:
```tsx
import { BrowserRouter, Route, Routes } from "react-router";
import { RequireAuth } from "@/auth/RequireAuth";
import { LoginPage } from "@/pages/acesso/LoginPage";
import { DefinirSenhaPage } from "@/pages/acesso/DefinirSenhaPage";
import { RedefinirSenhaPage } from "@/pages/acesso/RedefinirSenhaPage";
import { EsqueciSenhaPage } from "@/pages/acesso/EsqueciSenhaPage";
import { RotasApp } from "@/shell/rotasModulos";

export function AppRoutes() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/definir-senha" element={<DefinirSenhaPage />} />
        <Route path="/redefinir-senha" element={<RedefinirSenhaPage />} />
        <Route path="/esqueci-senha" element={<EsqueciSenhaPage />} />
        <Route element={<RequireAuth />}>{RotasApp()}</Route>
      </Routes>
    </BrowserRouter>
  );
}
```

`src/shell/rotasModulos.tsx` (placeholder **criado nesta task**, substituído em T10 — acrescentar a `Files: Create`):
```tsx
import { Route } from "react-router";

export function RotasApp() {
  return <Route path="/" element={<h1>Meridiano</h1>} />;
}
```

`App.tsx`:
```tsx
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "@/api/queryClient";
import { AuthProvider } from "@/auth/AuthProvider";
import { ToastHost } from "@/components/feedback";
import { AppRoutes } from "@/router";

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <AppRoutes />
        <ToastHost />
      </AuthProvider>
    </QueryClientProvider>
  );
}
```

`App.test.tsx` (substitui o de T01):
```tsx
import { render, screen } from "@testing-library/react";
import { App } from "./App";

test("sem sessão cai no login", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(null, { status: 401 }));
  window.history.pushState({}, "", "/");
  render(<App />);
  expect(await screen.findByRole("heading", { name: "Entrar" })).toBeInTheDocument();
});
```

- [ ] **Step 6: Rodar** — `npm run test && npm run lint && npm run typecheck` → verde. Manual: `cd backend && docker compose up -d && dotnet run --project src/Meridiano.Api` + `cd frontend && npm run dev`; abrir `http://localhost:5173/login`, entrar com o usuário de dev (ver `backend/docs/dev.md`) e ver "Meridiano".

- [ ] **Step 7: Reportar arquivos tocados**

Commit sugerido: `feat(auth): auth provider, route guard and access pages (login, invite, forgot, reset)`

---

### Task 10: AppShell — Sidebar por configuração, GlobalHeader, Page, PageHeader, Section, Subnav, Tabs, rotas dos módulos com EmptyState

**Files:**
- Create: `frontend/src/shell/AppShell.tsx`, `AppShell.module.css`, `Sidebar.tsx`, `Sidebar.module.css`, `Sidebar.test.tsx`, `GlobalHeader.tsx`, `GlobalHeader.module.css`, `navegacao.ts`, `EmConstrucao.tsx`
- Modify: `frontend/src/shell/rotasModulos.tsx`
- Create: `frontend/src/components/Page/Page.tsx`, `PageHeader.tsx`, `Section.tsx`, `Page.module.css`, `frontend/src/components/Subnav/Subnav.tsx`, `Subnav.module.css`, `frontend/src/components/Tabs/Tabs.tsx`, `Tabs.module.css`, `Tabs.test.tsx`, `frontend/src/components/shell.ts` (barrel)

**Depends-on:** T09 (useAuth), T04, T05, T07 (atalho Ctrl+K), T08

**Interfaces:**
- Produces:
  - `navegacao.ts`: `itensSidebar: { label; icon: LucideIcon; path; section: "Operação" | "Administração"; permission: string }[]` — Viagens (`viagem.ver` ou `viagem.ver_proprias`), Clientes (`cliente.ver` ou `cliente.ver_proprios`), Fornecedores (`viagem.ver`), Financeiro (`financeiro.movimentar` ou `financeiro.conciliar`), Agenda (`viagem.ver` ou `viagem.ver_proprias`), Relatórios (`relatorio.ver`), Equipe (`usuario.gerenciar`), Auditoria (`auditoria.ver`). `permission` aceita `string | string[]` (qualquer uma). Badges ficam para os subplanos.
  - `subnavs: Record<string, {label; path}[]>` — Financeiro: Conciliação `/financeiro` · Repasses `/financeiro/repasses` · Despesas `/financeiro/despesas` · Fechamento `/financeiro/fechamento`; Clientes: Pessoas `/clientes` · Grupos `/clientes/grupos`.
  - `<AppShell />` (Outlet) · `<Page>` · `<PageHeader title meta? status? dirty? actions? subtitle? />` · `<Section title? description?>` · `<Subnav items />` · `<Tabs tabs: {id; label; count?}[] active onChange>` + `<Tabs.Panel id active>`; máximo 6 tabs (`console.warn` acima disso em dev).
  - Sidebar colapsa em ícones abaixo de 1280 e vira gaveta abaixo de 1024 (botão ☰ no header).

- [ ] **Step 1: Testes**

`Sidebar.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { AuthContext, type AuthValue } from "@/auth/AuthProvider";
import { Sidebar } from "./Sidebar";

function comPermissoes(permissoes: string[]) {
  const v: AuthValue = { me: { usuarioId: "1", agenciaId: "2", perfil: "agente", nome: "A", permissoes }, carregando: false, pode: (p) => permissoes.includes(p), entrar: async () => undefined, sair: async () => undefined, recarregar: async () => undefined };
  return render(<AuthContext.Provider value={v}><MemoryRouter><Sidebar /></MemoryRouter></AuthContext.Provider>);
}

test("esconde itens sem permissão", () => {
  comPermissoes(["viagem.ver_proprias", "cliente.ver_proprios"]);
  expect(screen.getByRole("link", { name: /Viagens/ })).toBeInTheDocument();
  expect(screen.queryByRole("link", { name: /Equipe/ })).toBeNull();
  expect(screen.queryByText("Administração")).toBeNull();
});
```

`Tabs.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { Tabs } from "./Tabs";

function Harness() {
  const [a, setA] = useState("reservas");
  return (
    <Tabs tabs={[{ id: "reservas", label: "Reservas", count: 3 }, { id: "financeiro", label: "Financeiro" }]} active={a} onChange={setA}>
      <Tabs.Panel id="reservas" active={a}>R</Tabs.Panel>
      <Tabs.Panel id="financeiro" active={a}>F</Tabs.Panel>
    </Tabs>
  );
}

test("tab acessível com setas e painel único", async () => {
  render(<Harness />);
  expect(screen.getByRole("tab", { name: /Reservas/ })).toHaveAttribute("aria-selected", "true");
  expect(screen.getByRole("tabpanel")).toHaveTextContent("R");
  screen.getByRole("tab", { name: /Reservas/ }).focus();
  await userEvent.keyboard("{ArrowRight}");
  expect(screen.getByRole("tabpanel")).toHaveTextContent("F");
});
```

- [ ] **Step 2: Rodar para ver falhar** — FAIL.

- [ ] **Step 3: `navegacao.ts`**

```ts
import { BriefcaseBusiness, CalendarDays, ChartColumn, Plane, ShieldCheck, Users, UsersRound, Wallet, type LucideIcon } from "lucide-react";

export interface ItemSidebar { label: string; icon: LucideIcon; path: string; section: "Operação" | "Administração"; permission: string | string[] }

export const itensSidebar: ItemSidebar[] = [
  { label: "Viagens", icon: Plane, path: "/viagens", section: "Operação", permission: ["viagem.ver", "viagem.ver_proprias"] },
  { label: "Clientes", icon: Users, path: "/clientes", section: "Operação", permission: ["cliente.ver", "cliente.ver_proprios"] },
  { label: "Fornecedores", icon: BriefcaseBusiness, path: "/fornecedores", section: "Operação", permission: "viagem.ver" },
  { label: "Financeiro", icon: Wallet, path: "/financeiro", section: "Operação", permission: ["financeiro.movimentar", "financeiro.conciliar"] },
  { label: "Agenda", icon: CalendarDays, path: "/agenda", section: "Operação", permission: ["viagem.ver", "viagem.ver_proprias"] },
  { label: "Relatórios", icon: ChartColumn, path: "/relatorios", section: "Operação", permission: "relatorio.ver" },
  { label: "Equipe", icon: UsersRound, path: "/equipe", section: "Administração", permission: "usuario.gerenciar" },
  { label: "Auditoria", icon: ShieldCheck, path: "/auditoria", section: "Administração", permission: "auditoria.ver" },
];

export const subnavs: Record<string, { label: string; path: string }[]> = {
  "/financeiro": [
    { label: "Conciliação", path: "/financeiro" },
    { label: "Repasses", path: "/financeiro/repasses" },
    { label: "Despesas", path: "/financeiro/despesas" },
    { label: "Fechamento", path: "/financeiro/fechamento" },
  ],
  "/clientes": [
    { label: "Pessoas", path: "/clientes" },
    { label: "Grupos", path: "/clientes/grupos" },
  ],
};

export function temPermissao(pode: (p: string) => boolean, permission: string | string[]) {
  return Array.isArray(permission) ? permission.some(pode) : pode(permission);
}
```
(Conferir as chaves exatas em `backend/src/Meridiano.Domain/Comum/Permissao.cs` — `Chave()` — antes de fechar.)

- [ ] **Step 4: Sidebar, GlobalHeader, AppShell**

`Sidebar.tsx`:
```tsx
import { NavLink } from "react-router";
import { useAuth } from "@/auth/useAuth";
import { cx } from "@/lib/cx";
import { itensSidebar, temPermissao } from "./navegacao";
import s from "./Sidebar.module.css";

export function Sidebar({ aberta = false, onFechar }: { aberta?: boolean; onFechar?: () => void }) {
  const { pode } = useAuth();
  const visiveis = itensSidebar.filter((i) => temPermissao(pode, i.permission));
  const secoes = ["Operação", "Administração"] as const;
  return (
    <nav className={cx(s.side, aberta && s.aberta)} aria-label="Principal">
      <div className={s.brand}>Meridiano</div>
      {secoes.map((sec) => {
        const itens = visiveis.filter((i) => i.section === sec);
        if (!itens.length) return null;
        return (
          <div key={sec} className={s.secao}>
            <div className={s.secaoTitulo}>{sec}</div>
            {itens.map(({ label, icon: Icon, path }) => (
              <NavLink key={path} to={path} onClick={onFechar} className={({ isActive }) => cx(s.item, isActive && s.ativo)}>
                <Icon size={18} aria-hidden />
                <span className={s.label}>{label}</span>
              </NavLink>
            ))}
          </div>
        );
      })}
    </nav>
  );
}
```

`Sidebar.module.css`:
```css
.side { width: var(--sidebar-w); background: var(--sidebar-bg); color: var(--sidebar-text); display: flex; flex-direction: column; padding: var(--space-3) 0; height: 100vh; position: sticky; top: 0; }
.brand { font: var(--type-component); color: var(--color-text-inverse); padding: var(--space-3) var(--sidebar-pad-x); margin-bottom: var(--space-4); }
.secao { display: flex; flex-direction: column; margin-bottom: var(--space-4); }
.secaoTitulo { font: var(--type-caption); letter-spacing: var(--tracking-caps); text-transform: uppercase; opacity: 0.6; padding: var(--space-2) var(--sidebar-pad-x); }
.item { display: flex; align-items: center; gap: var(--sidebar-gap); height: var(--sidebar-row-h); padding: 0 var(--sidebar-pad-x); color: inherit; text-decoration: none; font: var(--type-label); border-left: 3px solid transparent; }
.item:hover { background: var(--sidebar-hover); }
.ativo { background: var(--sidebar-active); color: var(--color-text-inverse); border-left-color: var(--color-action-business); }
@media (max-width: 1280px) { .side { width: 64px; } .label, .secaoTitulo, .brand { display: none; } .item { justify-content: center; padding: 0; } }
@media (max-width: 1024px) { .side { position: fixed; left: -240px; top: 0; width: var(--sidebar-w); z-index: 40; transition: left 0.2s; box-shadow: var(--shadow-modal); } .aberta { left: 0; } .label, .secaoTitulo, .brand { display: block; } .item { justify-content: flex-start; padding: 0 var(--sidebar-pad-x); } }
```

`GlobalHeader.tsx`:
```tsx
import { useRef } from "react";
import { Bell, CircleHelp, LogOut, Menu, Plus, Search } from "lucide-react";
import { useNavigate } from "react-router";
import { useAuth } from "@/auth/useAuth";
import { Button, IconButton, Input } from "@/components";
import { useAtalho } from "@/lib/useAtalho";
import s from "./GlobalHeader.module.css";

export function GlobalHeader({ onMenu }: { onMenu: () => void }) {
  const { me, pode, sair } = useAuth();
  const nav = useNavigate();
  const busca = useRef<HTMLInputElement>(null);
  useAtalho("ctrl+k", () => busca.current?.focus());
  return (
    <header className={s.top}>
      <IconButton label="Menu" icon={<Menu size={20} />} onClick={onMenu} className={s.menu} />
      <div className={s.busca}>
        <Search size={16} aria-hidden className={s.buscaIcone} />
        <Input ref={busca} aria-label="Buscar" placeholder="Buscar cliente, viagem, localizador…" />
        <kbd className={s.kbd}>Ctrl K</kbd>
      </div>
      {pode("viagem.criar") && (
        <Button variant="secondary" icon={<Plus size={16} />} onClick={() => nav("/viagens/nova")}>Nova viagem</Button>
      )}
      <IconButton label="Notificações" icon={<Bell size={20} />} />
      <IconButton label="Ajuda" icon={<CircleHelp size={20} />} />
      <div className={s.user}>
        <span className={s.nome}>{me?.nome}</span>
        <IconButton label="Sair" icon={<LogOut size={20} />} onClick={() => { void sair().then(() => nav("/login")); }} />
      </div>
    </header>
  );
}
```

`GlobalHeader.module.css`:
```css
.top { height: var(--topbar-h); display: flex; align-items: center; gap: var(--space-3); padding: 0 var(--space-6); background: var(--color-bg-surface); border-bottom: 1px solid var(--color-border); position: sticky; top: 0; z-index: 30; }
.menu { display: none; }
.busca { position: relative; flex: 1; max-width: 460px; display: flex; align-items: center; }
.busca input { padding-left: var(--space-8); padding-right: var(--space-12); }
.buscaIcone { position: absolute; left: var(--space-3); color: var(--color-text-muted); pointer-events: none; }
.kbd { position: absolute; right: var(--space-3); font: var(--type-code); color: var(--color-text-muted); background: var(--color-bg-subtle); padding: 0 var(--space-1); border-radius: var(--radius-sm); }
.user { margin-left: auto; display: flex; align-items: center; gap: var(--space-2); }
.nome { font: var(--type-label); color: var(--color-text-secondary); }
@media (max-width: 1024px) { .menu { display: inline-flex; } .nome { display: none; } }
```

`AppShell.tsx`:
```tsx
import { useEffect, useState } from "react";
import { Outlet, useLocation } from "react-router";
import { instalarAtalhos } from "@/lib/atalhos";
import { GlobalHeader } from "./GlobalHeader";
import { Sidebar } from "./Sidebar";
import s from "./AppShell.module.css";

export function AppShell() {
  const [menu, setMenu] = useState(false);
  const loc = useLocation();
  useEffect(instalarAtalhos, []);
  useEffect(() => setMenu(false), [loc.pathname]);
  return (
    <div className={s.shell}>
      <Sidebar aberta={menu} onFechar={() => setMenu(false)} />
      <div className={s.main}>
        <GlobalHeader onMenu={() => setMenu((m) => !m)} />
        <Outlet />
      </div>
    </div>
  );
}
```

`AppShell.module.css`:
```css
.shell { display: flex; min-height: 100vh; }
.main { flex: 1; min-width: 0; display: flex; flex-direction: column; }
```

- [ ] **Step 5: Page, PageHeader, Section, Subnav, Tabs**

`Page.module.css`:
```css
.page { padding: var(--space-6); max-width: var(--content-max); width: 100%; margin: 0 auto; display: flex; flex-direction: column; gap: var(--space-8); }
.head { display: flex; align-items: flex-start; gap: var(--space-4); flex-wrap: wrap; }
.titulo { font: var(--type-page); color: var(--color-text-heading); display: flex; align-items: center; gap: var(--space-3); }
.subtitulo { font: var(--type-body); color: var(--color-text-secondary); margin-top: var(--space-1); }
.acoes { margin-left: auto; display: flex; gap: var(--space-2); align-items: center; }
.dirty { font: var(--type-label); color: var(--color-dirty); display: inline-flex; align-items: center; gap: var(--space-1); }
.section { display: flex; flex-direction: column; gap: var(--space-4); }
.sectionTitulo { font: var(--type-section); color: var(--color-text-heading); }
.sectionDesc { font: var(--type-body); color: var(--color-text-secondary); }
@media (max-width: 1024px) { .page { padding: var(--space-4); } .acoes { margin-left: 0; width: 100%; } }
```

`Page.tsx`:
```tsx
import type { ReactNode } from "react";
import s from "./Page.module.css";
export function Page({ children }: { children: ReactNode }) {
  return <main className={s.page}>{children}</main>;
}
```

`PageHeader.tsx`:
```tsx
import type { ReactNode } from "react";
import s from "./Page.module.css";

interface PageHeaderProps { title: string; subtitle?: string; meta?: ReactNode; status?: ReactNode; dirty?: boolean; actions?: ReactNode }

export function PageHeader({ title, subtitle, meta, status, dirty, actions }: PageHeaderProps) {
  return (
    <header className={s.head}>
      <div>
        <h1 className={s.titulo}>{title}{meta}{status}</h1>
        {subtitle && <p className={s.subtitulo}>{subtitle}</p>}
      </div>
      <div className={s.acoes}>
        {dirty && <span className={s.dirty} aria-live="polite">● Alterações não salvas</span>}
        {actions}
      </div>
    </header>
  );
}
```

`Section.tsx`:
```tsx
import type { ReactNode } from "react";
import s from "./Page.module.css";
export function Section({ title, description, children }: { title?: string; description?: string; children: ReactNode }) {
  return (
    <section className={s.section}>
      {title && <h2 className={s.sectionTitulo}>{title}</h2>}
      {description && <p className={s.sectionDesc}>{description}</p>}
      {children}
    </section>
  );
}
```

`Subnav.tsx` + css:
```tsx
import { NavLink } from "react-router";
import { cx } from "@/lib/cx";
import s from "./Subnav.module.css";
export function Subnav({ items }: { items: { label: string; path: string }[] }) {
  return (
    <nav className={s.subnav} aria-label="Seções do módulo">
      {items.map((i) => (
        <NavLink key={i.path} to={i.path} end className={({ isActive }) => cx(s.item, isActive && s.ativo)}>{i.label}</NavLink>
      ))}
    </nav>
  );
}
```
```css
.subnav { display: flex; gap: var(--space-1); border-bottom: 1px solid var(--color-border); padding: 0 var(--space-6); background: var(--color-bg-surface); }
.item { padding: var(--space-3) var(--space-3); font: var(--type-label); color: var(--color-text-secondary); text-decoration: none; border-bottom: 2px solid transparent; }
.item:hover { color: var(--color-text-primary); }
.ativo { color: var(--color-text-heading); border-bottom-color: var(--color-action); }
```

`Tabs.tsx`:
```tsx
import { useRef, type KeyboardEvent, type ReactNode } from "react";
import { cx } from "@/lib/cx";
import s from "./Tabs.module.css";

export interface Tab { id: string; label: string; count?: number }
interface TabsProps { tabs: Tab[]; active: string; onChange: (id: string) => void; children: ReactNode }

export function Tabs({ tabs, active, onChange, children }: TabsProps) {
  const lista = useRef<HTMLDivElement>(null);
  if (import.meta.env.DEV && tabs.length > 6) console.warn("Tabs: máximo 6 (contrato §4.5)");
  function teclas(e: KeyboardEvent) {
    const i = tabs.findIndex((t) => t.id === active);
    const prox = e.key === "ArrowRight" ? (i + 1) % tabs.length : e.key === "ArrowLeft" ? (i - 1 + tabs.length) % tabs.length : -1;
    if (prox < 0) return;
    e.preventDefault();
    onChange(tabs[prox]!.id);
    lista.current?.querySelectorAll<HTMLButtonElement>("[role=tab]")[prox]?.focus();
  }
  return (
    <div className={s.wrap}>
      <div ref={lista} role="tablist" className={s.list} onKeyDown={teclas}>
        {tabs.map((t) => (
          <button key={t.id} type="button" role="tab" id={`tab-${t.id}`} aria-selected={t.id === active} aria-controls={`panel-${t.id}`} tabIndex={t.id === active ? 0 : -1} className={cx(s.tab, t.id === active && s.ativo)} onClick={() => onChange(t.id)}>
            {t.label}{t.count !== undefined && <span className={s.count}>{t.count}</span>}
          </button>
        ))}
      </div>
      {children}
    </div>
  );
}

Tabs.Panel = function Panel({ id, active, children }: { id: string; active: string; children: ReactNode }) {
  if (id !== active) return null;
  return <div role="tabpanel" id={`panel-${id}`} aria-labelledby={`tab-${id}`} className={s.panel}>{children}</div>;
};
```
```css
.wrap { display: flex; flex-direction: column; gap: var(--space-6); }
.list { display: flex; gap: var(--space-1); border-bottom: 1px solid var(--color-border); }
.tab { background: none; border: 0; border-bottom: 2px solid transparent; padding: var(--space-3) var(--space-3); font: var(--type-label); color: var(--color-text-secondary); cursor: pointer; display: inline-flex; gap: var(--space-2); align-items: center; }
.ativo { color: var(--color-text-heading); border-bottom-color: var(--color-action); }
.count { font: var(--type-caption); background: var(--color-neutral-soft); color: var(--color-neutral-text); border-radius: var(--radius-pill); padding: 0 var(--space-2); }
.panel { display: flex; flex-direction: column; gap: var(--space-6); }
```

`shell.ts` barrel:
```ts
export { Page } from "./Page/Page";
export { PageHeader } from "./Page/PageHeader";
export { Section } from "./Page/Section";
export { Subnav } from "./Subnav/Subnav";
export { Tabs, type Tab } from "./Tabs/Tabs";
```

- [ ] **Step 6: Rotas dos módulos com EmptyState "em construção"**

`EmConstrucao.tsx`:
```tsx
import { Construction } from "lucide-react";
import { Page, PageHeader, Subnav } from "@/components/shell";
import { EmptyState } from "@/components/feedback";
import { useLocation } from "react-router";
import { subnavs } from "./navegacao";

export function EmConstrucao({ titulo }: { titulo: string }) {
  const { pathname } = useLocation();
  const modulo = Object.keys(subnavs).find((k) => pathname.startsWith(k));
  return (
    <>
      {modulo && <Subnav items={subnavs[modulo]!} />}
      <Page>
        <PageHeader title={titulo} />
        <EmptyState icon={<Construction size={32} />} title="Em construção" description="Esta tela chega no próximo subplano da Fase 3." />
      </Page>
    </>
  );
}
```

`rotasModulos.tsx` (substitui o placeholder de T09):
```tsx
import { Navigate, Route } from "react-router";
import { AppShell } from "./AppShell";
import { EmConstrucao } from "./EmConstrucao";

export function RotasApp() {
  return (
    <Route element={<AppShell />}>
      <Route index element={<Navigate to="/viagens" replace />} />
      <Route path="/viagens" element={<EmConstrucao titulo="Viagens" />} />
      <Route path="/viagens/nova" element={<EmConstrucao titulo="Nova viagem" />} />
      <Route path="/clientes" element={<EmConstrucao titulo="Clientes" />} />
      <Route path="/clientes/grupos" element={<EmConstrucao titulo="Grupos" />} />
      <Route path="/fornecedores" element={<EmConstrucao titulo="Fornecedores" />} />
      <Route path="/financeiro" element={<EmConstrucao titulo="Conciliação" />} />
      <Route path="/financeiro/repasses" element={<EmConstrucao titulo="Repasses" />} />
      <Route path="/financeiro/despesas" element={<EmConstrucao titulo="Despesas" />} />
      <Route path="/financeiro/fechamento" element={<EmConstrucao titulo="Fechamento" />} />
      <Route path="/agenda" element={<EmConstrucao titulo="Agenda" />} />
      <Route path="/relatorios" element={<EmConstrucao titulo="Relatórios" />} />
      <Route path="/equipe" element={<EmConstrucao titulo="Equipe" />} />
      <Route path="/auditoria" element={<EmConstrucao titulo="Auditoria" />} />
      <Route path="*" element={<EmConstrucao titulo="Página não encontrada" />} />
    </Route>
  );
}
```
(`App.test.tsx` de T09 continua válido: sem sessão cai no login.)

- [ ] **Step 7: Rodar** — `npm run test && npm run lint && npm run typecheck && npm run build` → verde. Manual: logar e navegar pela sidebar; reduzir a janela a 1200 e 900 px e ver colapso/gaveta.

- [ ] **Step 8: Reportar arquivos tocados**

Commit sugerido: `feat(shell): app shell with permission-driven sidebar, header, page, subnav and tabs`

---

### Task 11: Styleguide `/styleguide` (dev) e Playwright — regressão visual e E2E de login

**Files:**
- Create: `frontend/src/pages/styleguide/StyleguidePage.tsx`, `StyleguidePage.module.css`, `frontend/playwright.config.ts`, `frontend/e2e/styleguide.spec.ts`, `frontend/e2e/login.spec.ts`, `frontend/e2e/fixtures.ts`
- Modify: `frontend/src/router.tsx` (rota `/styleguide` só com `import.meta.env.DEV`), `frontend/.github/workflows/ci.yml` (job e2e)

**Depends-on:** T10

**Interfaces:**
- Produces: página com todas as seções: botões (5 variantes × normal/loading/disabled), campos (normal · erro · calculado · readonly · disabled), MoneyInput/MoneyValue, chips on/off, badges por tone e por `StatusBadge` de cada entidade, alertas, toast (botões que disparam), modal e ConfirmModal, skeleton, empty state, tabs, page header com dirty. Snapshots Playwright em 1280 e 1440. E2E de login contra a API real (Docker) com usuário semeado.

- [ ] **Step 1: `StyleguidePage.tsx`** — uma `Section` por grupo, usando só os barrels. Exemplo do bloco de campos (repetir o padrão para os demais):

```tsx
<Section title="Campos" description="Cinco estados: editável, erro, calculado, somente leitura, desabilitado">
  <div className={s.grid}>
    <Field label="Editável" required helper="Texto de ajuda"><Input defaultValue="CVC Operadora" /></Field>
    <Field label="Com erro" error="Localizador já usado nesta viagem"><Input defaultValue="ABC123" /></Field>
    <Field label="Calculado" tooltip="Venda − custo"><MoneyInput value={1600} onChange={() => undefined} calculated /></Field>
    <Field label="Somente leitura"><Input readOnly defaultValue="VG-2026-0042" /></Field>
    <Field label="Desabilitado"><Input disabled defaultValue="—" /></Field>
    <Field label="Data"><DateInput defaultValue="2026-09-08" /></Field>
    <Field label="Select"><Select placeholder="Escolha" options={[{ value: "pix", label: "Pix" }, { value: "boleto", label: "Boleto" }]} /></Field>
  </div>
</Section>
```
Grid: `.grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: var(--space-4); } .grid > * { grid-column: span 3; }` em `StyleguidePage.module.css`. Cada `Section` recebe `data-testid="sg-<nome>"` via wrapper `<div data-testid=…>` para os snapshots.

Rota em `router.tsx`, dentro do `<Route element={<RequireAuth />}>` **não** — fora, pública e só em dev:
```tsx
{import.meta.env.DEV && <Route path="/styleguide" element={<StyleguidePage />} />}
```

- [ ] **Step 2: `playwright.config.ts`**

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  timeout: 30_000,
  expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.01 } },
  use: { baseURL: "http://localhost:5173", trace: "retain-on-failure" },
  webServer: { command: "npm run dev", url: "http://localhost:5173", reuseExistingServer: !process.env.CI },
  projects: [
    { name: "1280", use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 900 } } },
    { name: "1440", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
  ],
});
```
`npx playwright install chromium`.

- [ ] **Step 3: `e2e/styleguide.spec.ts`**

```ts
import { expect, test } from "@playwright/test";

const secoes = ["botoes", "campos", "dinheiro", "chips-badges", "alertas", "tabs", "page-header"];

for (const sec of secoes) {
  test(`styleguide ${sec}`, async ({ page }) => {
    await page.goto("/styleguide");
    const el = page.getByTestId(`sg-${sec}`);
    await expect(el).toBeVisible();
    await expect(el).toHaveScreenshot(`${sec}.png`);
  });
}

test("modal aberto", async ({ page }) => {
  await page.goto("/styleguide");
  await page.getByRole("button", { name: "Abrir modal de decisão" }).click();
  await expect(page.getByRole("dialog")).toHaveScreenshot("modal.png");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
});
```
Primeira execução gera os snapshots: `npx playwright test --update-snapshots`. Commitar `e2e/styleguide.spec.ts-snapshots/`.

- [ ] **Step 4: `e2e/fixtures.ts` e `e2e/login.spec.ts`** — login contra a API real. Pré-condição: `backend` rodando com o usuário de dev. Não existe usuário semeado hoje (`backend/scripts/postgres-init.sql` só cria roles e banco). Esta task cria o script `backend/scripts/seed-dev.sql` (agência "Viva Turismo", `dono@viva.dev` / senha `meridiano123`) e documenta em `dev.md` — arquivo do repo backend, commit separado.

```ts
// fixtures.ts
export const DEV_USER = { email: process.env.E2E_EMAIL ?? "dono@viva.dev", senha: process.env.E2E_SENHA ?? "meridiano123" };
```
```ts
// login.spec.ts
import { expect, test } from "@playwright/test";
import { DEV_USER } from "./fixtures";

test("login e navegação pela sidebar", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveURL(/\/login/);
  await page.getByLabel(/E-mail/).fill(DEV_USER.email);
  await page.getByLabel(/Senha/).fill(DEV_USER.senha);
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page).toHaveURL(/\/viagens/);
  await page.getByRole("link", { name: /Financeiro/ }).click();
  await expect(page.getByRole("heading", { name: "Conciliação" })).toBeVisible();
  await page.getByRole("button", { name: "Sair" }).click();
  await expect(page).toHaveURL(/\/login/);
});

test("senha errada", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel(/E-mail/).fill(DEV_USER.email);
  await page.getByLabel(/Senha/).fill("errada");
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page.getByRole("alert")).toHaveText("E-mail ou senha incorretos.");
});
```

- [ ] **Step 5: CI — job `e2e`** (acrescentar ao `ci.yml`; só styleguide no CI; login E2E precisa da API e fica para o CI de integração da Fase 4):

```yaml
  e2e:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 24, cache: npm }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - run: npx playwright test e2e/styleguide.spec.ts
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: playwright-report, path: playwright-report }
```

- [ ] **Step 6: Rodar** — `npm run test:e2e` local com API + Docker rodando → 2 projetos × (7 + 1 + 2) testes verdes.

- [ ] **Step 7: Reportar arquivos tocados**

Commit sugerido: `test(e2e): styleguide visual regression at 1280/1440 and login flow`

---

### Task 12: Documentação e fechamento do subplano

**Files:**
- Modify: `frontend/README.md`, `CLAUDE.md` (root: comandos do front já listados; confirmar), `docs/BACKLOG.md` (fase 3.1 concluída; pendência `AddModules` e `GET /auth/tokens` resolvidas), `.claude/SETUP-BACKLOG.md` (itens 1–3 concluídos), `backend/docs/dev.md` (build com front: `docker build -f backend/Dockerfile .` na pasta pai; usuário de dev)

**Depends-on:** T11

- [ ] **Step 1:** `frontend/README.md` — estrutura de pastas (`api/ auth/ components/ dominio/ lib/ pages/ shell/ styles/`), scripts, regra dos barrels (`components/index.ts` primitivos · `display.ts` · `feedback.ts` · `shell.ts`), como rodar E2E.
- [ ] **Step 2:** `docs/BACKLOG.md` — linha 3.1 concluída com data; remover as duas pendências resolvidas; anotar snapshot Playwright como baseline.
- [ ] **Step 3:** `.claude/SETUP-BACKLOG.md` — marcar 1, 2, 3 como concluídos.
- [ ] **Step 4:** Controlador commita nos três repos e faz `develop` → `main` (ff) + push.

---

## Self-review (feito ao escrever)

- **Cobertura:** contrato §3 até `Section` ✓ (ReservationCard/TripSummary/DataTable/KpiCard ficam em 3.2/3.3 como o contrato manda); §4 erros/estado ✓ (T03, T07); §5 proibições ✓ (T02 lint); §6 a11y ✓ (Field/Modal/Tabs/Chip); §7 styleguide + regressão visual ✓ (T11); telas 01–04 ✓ (T09); shell com sidebar/subnav/tabs ✓ (T10); pendências Fase 2 `AddModules` ✓ (T06). Fora: teste de UX §7 (fim da Fase 3), badges da sidebar (subplanos).
- **Placeholders:** nenhum "TBD"; onde há decisão condicional (versão do Biome) o passo diz exatamente o que verificar e o que fazer.
- **Tipos:** `Me.permissoes: string[]` = `MeResponse.Permissoes` ✓; `TokenInfo {nome,email,tipo}` = `ConviteService.TokenInfo` serializado camelCase ✓; `apresentacaoStatus(entidade, valor)` usado por `StatusBadge` ✓; `useAtalho("escape")` em `Modal` e `"ctrl+k"` em `GlobalHeader` ✓; barrels: `@/components` (T04), `@/components/display` (T05), `@/components/feedback` (T08), `@/components/shell` (T10) ✓; `AuthContext`/`AuthValue` exportados por `AuthProvider.tsx` e usados em `Sidebar.test.tsx` ✓.
