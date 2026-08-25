import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = join(ROOT, "public");
const DEFAULT_PORT = Number(process.env.PORT || 4173);
const MAX_BODY_BYTES = 64 * 1024;
const MAX_OUTPUT_BYTES = 64 * 1024;

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

const learningCatalog = {
  E0502: {
    eyebrow: "Borrow checker · конфликт займов",
    title: "Изменяемый и неизменяемый займы пересеклись",
    summary:
      "Ссылка сохраняет неизменяемый заём активным до её последнего использования. Изменять исходный Vec в этом интервале нельзя.",
    rule: "В один момент у значения может быть либо много неизменяемых ссылок, либо одна изменяемая.",
    repairTitle: "Сначала используй ссылку, затем изменяй Vec",
    practice: {
      title: "Освободи заём до изменения",
      prompt:
        "Сделай так, чтобы имя вывелось, а затем в вектор добавился Ferris. Код должен скомпилироваться и напечатать Ada.",
      starter: `fn main() {
    let mut names = vec!["Ada", "Linus"];
    let first = &names[0];
    names.push("Ferris");
    println!("{first}");
}`,
      expectedOutput: "Ada",
    },
  },
  E0382: {
    eyebrow: "Ownership · перемещение значения",
    title: "Значение было перемещено",
    summary:
      "Операция передала владение значением. Старую переменную после этого использовать нельзя, если тип не реализует Copy.",
    rule: "У каждого значения есть один владелец; передача владения делает прежнее имя недоступным.",
    repairTitle: "Передай ссылку или явно клонируй значение",
  },
  E0499: {
    eyebrow: "Borrow checker · изменяемые ссылки",
    title: "Два изменяемых займа живут одновременно",
    summary:
      "Первый &mut всё ещё используется, когда создаётся второй. Rust запрещает одновременную запись через два пути.",
    rule: "Одновременно может существовать только одна активная изменяемая ссылка на значение.",
    repairTitle: "Заверши использование первого &mut раньше",
  },
  E0596: {
    eyebrow: "Mutability · доступ к записи",
    title: "Значение нельзя изменить",
    summary:
      "Переменная или ссылка объявлена неизменяемой, но код пытается выполнить операцию записи.",
    rule: "Изменение разрешено только через mut-переменную или &mut-ссылку.",
    repairTitle: "Добавь mut там, где действительно нужна запись",
  },
};

function runProcess(command, args, options = {}) {
  const timeoutMs = options.timeoutMs ?? 8000;
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;

    const append = (current, chunk) =>
      (current + chunk.toString("utf8")).slice(0, MAX_OUTPUT_BYTES);

    child.stdout.on("data", (chunk) => {
      stdout = append(stdout, chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr = append(stderr, chunk);
    });
    child.on("error", (error) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(error);
      }
    });
    child.on("close", (code, signal) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve({ code, signal, stdout, stderr, timedOut: false });
      }
    });

    const timer = setTimeout(() => {
      if (settled) return;
      child.kill("SIGKILL");
      settled = true;
      resolve({
        code: null,
        signal: "SIGKILL",
        stdout,
        stderr,
        timedOut: true,
      });
    }, timeoutMs);
  });
}

export function parseRustcDiagnostics(stderr) {
  return stderr
    .split("\n")
    .filter(Boolean)
    .flatMap((line) => {
      try {
        const item = JSON.parse(line);
        if (item.$message_type !== "diagnostic" || !item.code?.code) return [];
        return [
          {
            code: item.code.code,
            level: item.level,
            message: item.message,
            rendered: item.rendered,
            spans: item.spans
              .filter((span) => span.file_name.endsWith("main.rs"))
              .map((span) => ({
                lineStart: span.line_start,
                lineEnd: span.line_end,
                columnStart: span.column_start,
                columnEnd: span.column_end,
                primary: span.is_primary,
                label: span.label,
                text: span.text?.[0]?.text ?? "",
              })),
          },
        ];
      } catch {
        return [];
      }
    });
}

function buildCausalSteps(diagnostic) {
  const spans = diagnostic.spans;
  if (diagnostic.code === "E0502") {
    const immutable = spans.find((span) => span.label?.includes("immutable borrow occurs"));
    const mutation = spans.find((span) => span.label?.includes("mutable borrow occurs"));
    const lastUse = spans.find((span) => span.label?.includes("later used"));
    return [
      immutable && {
        line: immutable.lineStart,
        tone: "cool",
        title: "Здесь начинается неизменяемый заём",
        detail: immutable.text.trim(),
      },
      lastUse && {
        line: lastUse.lineStart,
        tone: "cool",
        title: "До этой строки ссылка должна оставаться живой",
        detail: lastUse.text.trim(),
      },
      mutation && {
        line: mutation.lineStart,
        tone: "hot",
        title: "А здесь нужен изменяемый доступ",
        detail: mutation.text.trim(),
      },
      {
        line: mutation?.lineStart ?? spans[0]?.lineStart,
        tone: "hot",
        title: "Интервалы пересекаются — rustc отклоняет программу",
        detail: "Это предотвращает изменение памяти, пока на неё указывает активная ссылка.",
      },
    ].filter(Boolean);
  }

  return spans.slice(0, 3).map((span) => ({
    line: span.lineStart,
    tone: span.primary ? "hot" : "cool",
    title: span.label || diagnostic.message,
    detail: span.text.trim(),
  }));
}

function buildRepair(code, diagnostic) {
  if (diagnostic.code !== "E0502") return null;
  const mutation = diagnostic.spans.find((span) => span.label?.includes("mutable borrow occurs"));
  const lastUse = diagnostic.spans.find((span) => span.label?.includes("later used"));
  if (!mutation || !lastUse || mutation.lineStart >= lastUse.lineStart) return null;

  const lines = code.split("\n");
  const mutationIndex = mutation.lineStart - 1;
  const useIndex = lastUse.lineStart - 1;
  [lines[mutationIndex], lines[useIndex]] = [lines[useIndex], lines[mutationIndex]];
  return lines.join("\n");
}

function enrichDiagnostic(code, diagnostic) {
  const catalog = learningCatalog[diagnostic.code] ?? {
    eyebrow: "Rust compiler · диагностика",
    title: diagnostic.code,
    summary: diagnostic.message,
    rule: "Используй точные позиции и подсказки rustc, чтобы найти причину ошибки.",
    repairTitle: "Исправь отмеченную конструкцию",
  };
  return {
    ...diagnostic,
    learning: {
      ...catalog,
      causalSteps: buildCausalSteps(diagnostic),
      repairCode: buildRepair(code, diagnostic),
    },
  };
}

export async function compileRust(code, { run = false } = {}) {
  if (typeof code !== "string" || !code.trim()) {
    return { ok: false, kind: "input", message: "Добавьте Rust-код перед проверкой." };
  }
  if (Buffer.byteLength(code, "utf8") > MAX_BODY_BYTES) {
    return { ok: false, kind: "input", message: "Для POC код ограничен 64 КБ." };
  }

  const workDir = await mkdtemp(join(tmpdir(), "crabrix-poc-"));
  const sourcePath = join(workDir, "main.rs");
  const binaryPath = join(workDir, "program");

  try {
    await writeFile(sourcePath, code, "utf8");
    const compilation = await runProcess(
      "rustc",
      ["--edition", "2021", "--error-format=json", sourcePath, "-o", binaryPath],
      { cwd: workDir, timeoutMs: 10_000 },
    );
    const diagnostics = parseRustcDiagnostics(compilation.stderr).map((diagnostic) =>
      enrichDiagnostic(code, diagnostic),
    );

    if (compilation.timedOut) {
      return {
        ok: false,
        kind: "compiler-timeout",
        message: "Компилятор превысил лимит времени.",
        diagnostics,
      };
    }
    if (compilation.code !== 0) {
      return {
        ok: false,
        kind: "compile",
        message: diagnostics[0]?.message ?? "rustc завершился с ошибкой.",
        diagnostics,
      };
    }
    if (!run) {
      return { ok: true, kind: "check", diagnostics: [], stdout: "", stderr: "" };
    }

    const execution = await runProcess(binaryPath, [], { cwd: workDir, timeoutMs: 1500 });
    if (execution.timedOut) {
      return {
        ok: false,
        kind: "runtime-timeout",
        message: "Программа остановлена: лимит выполнения 1,5 секунды.",
        diagnostics: [],
        stdout: execution.stdout,
        stderr: execution.stderr,
      };
    }
    return {
      ok: execution.code === 0,
      kind: "run",
      message: execution.code === 0 ? "Программа выполнена." : "Программа завершилась с ошибкой.",
      diagnostics: [],
      stdout: execution.stdout,
      stderr: execution.stderr,
      exitCode: execution.code,
    };
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
}

async function readJsonBody(request) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body, "utf8") > MAX_BODY_BYTES) {
      throw new Error("request-too-large");
    }
  }
  return JSON.parse(body || "{}");
}

function sendJson(response, status, value) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(value));
}

async function serveStatic(pathname, response) {
  const normalized = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  if (normalized.includes("..")) {
    response.writeHead(400);
    response.end("Bad request");
    return;
  }
  const filePath = join(PUBLIC_DIR, normalized);
  try {
    const file = await readFile(filePath);
    response.writeHead(200, {
      "Content-Type": contentTypes[extname(filePath)] || "application/octet-stream",
      "Cache-Control": "no-cache",
    });
    response.end(file);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
  }
}

export function createCrabrixServer() {
  return createServer(async (request, response) => {
    const url = new URL(request.url || "/", "http://127.0.0.1");
    try {
      if (request.method === "GET" && url.pathname === "/api/health") {
        const version = await runProcess("rustc", ["--version"], { timeoutMs: 2000 });
        sendJson(response, 200, {
          ok: version.code === 0,
          rustc: version.stdout.trim() || "rustc unavailable",
          mode: "local-poc",
        });
        return;
      }
      if (request.method === "POST" && url.pathname === "/api/compile") {
        const body = await readJsonBody(request);
        const result = await compileRust(body.code, { run: Boolean(body.run) });
        sendJson(response, 200, result);
        return;
      }
      if (request.method !== "GET") {
        sendJson(response, 405, { error: "Method not allowed" });
        return;
      }
      await serveStatic(url.pathname, response);
    } catch (error) {
      const status = error.message === "request-too-large" ? 413 : 500;
      sendJson(response, status, {
        error: status === 413 ? "Request too large" : "Internal server error",
      });
    }
  });
}

const launchedDirectly = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (launchedDirectly) {
  const server = createCrabrixServer();
  server.listen(DEFAULT_PORT, "127.0.0.1", () => {
    console.log(`Crabrix POC: http://127.0.0.1:${DEFAULT_PORT}`);
  });
}
