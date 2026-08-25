const originalCode = `fn main() {
    let mut items = vec!["crab", "rust"];
    let first = &items[0];
    items.push("compiler");
    println!("{first}");
}`;

const state = {
  code: originalCode,
  diagnostic: null,
  lesson: null,
  busy: false,
  stages: new Set(),
  practiceCompleted: false,
};

const elements = {
  codeInput: document.querySelector("#codeInput"),
  codeHighlight: document.querySelector("#codeHighlight"),
  lineNumbers: document.querySelector("#lineNumbers"),
  checkButton: document.querySelector("#checkButton"),
  runButton: document.querySelector("#runButton"),
  resetButton: document.querySelector("#resetButton"),
  inlineDiagnostic: document.querySelector("#inlineDiagnostic"),
  inlineMessage: document.querySelector("#inlineMessage"),
  openExplanation: document.querySelector("#openExplanation"),
  consoleStatus: document.querySelector("#consoleStatus"),
  consoleContent: document.querySelector("#consoleContent"),
  problemCount: document.querySelector("#problemCount"),
  learningEmpty: document.querySelector("#learningEmpty"),
  learningCard: document.querySelector("#learningCard"),
  learningEyebrow: document.querySelector("#learningEyebrow"),
  learningTitle: document.querySelector("#learningTitle"),
  learningCode: document.querySelector("#learningCode"),
  learningSummary: document.querySelector("#learningSummary"),
  learningRule: document.querySelector("#learningRule"),
  causalTimeline: document.querySelector("#causalTimeline"),
  repairBox: document.querySelector("#repairBox"),
  repairTitle: document.querySelector("#repairTitle"),
  repairButton: document.querySelector("#repairButton"),
  practiceButton: document.querySelector("#practiceButton"),
  practiceDialog: document.querySelector("#practiceDialog"),
  practiceTitle: document.querySelector("#practiceTitle"),
  practicePrompt: document.querySelector("#practicePrompt"),
  practiceCode: document.querySelector("#practiceCode"),
  practiceFeedback: document.querySelector("#practiceFeedback"),
  checkPracticeButton: document.querySelector("#checkPracticeButton"),
  compilerPill: document.querySelector("#compilerPill"),
  compilerVersion: document.querySelector("#compilerVersion"),
  toast: document.querySelector("#toast"),
};

function escapeHtml(value) {
  return value.replace(/[&<>]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[character]);
}

function highlightLine(line) {
  const pattern = /(\/\/.*$|"(?:\\.|[^"\\])*"|\b(?:fn|let|mut|vec|pub|use|struct|impl|match|if|else|for|in|return|move|ref|self|Self|true|false)\b|\b\d+(?:\.\d+)?\b|&(?:mut\b)?)/g;
  let output = "";
  let cursor = 0;
  for (const match of line.matchAll(pattern)) {
    output += escapeHtml(line.slice(cursor, match.index));
    const token = match[0];
    let className = "tok-keyword";
    if (token.startsWith("//")) className = "tok-comment";
    else if (token.startsWith('"')) className = "tok-string";
    else if (/^\d/.test(token)) className = "tok-number";
    else if (token.startsWith("&")) className = "tok-borrow";
    output += `<span class="${className}">${escapeHtml(token)}</span>`;
    cursor = match.index + token.length;
  }
  output += escapeHtml(line.slice(cursor));
  return output || " ";
}

function renderEditor() {
  const lines = state.code.split("\n");
  const problemLines = new Set(state.diagnostic?.spans.filter((span) => span.primary).map((span) => span.lineStart) ?? []);
  elements.codeHighlight.innerHTML = lines
    .map((line, index) => {
      const content = highlightLine(line);
      return problemLines.has(index + 1) ? `<span class="problem-line">${content}</span>` : content;
    })
    .join("\n");
  elements.lineNumbers.innerHTML = lines
    .map((_, index) => `<span class="${problemLines.has(index + 1) ? "problem" : ""}">${index + 1}</span>`)
    .join("");
}

function syncEditorScroll() {
  elements.codeHighlight.scrollTop = elements.codeInput.scrollTop;
  elements.codeHighlight.scrollLeft = elements.codeInput.scrollLeft;
  elements.lineNumbers.style.transform = `translateY(${-elements.codeInput.scrollTop}px)`;
}

function setBusy(busy, label = "Компиляция…") {
  state.busy = busy;
  elements.checkButton.disabled = busy;
  elements.runButton.disabled = busy;
  elements.checkPracticeButton.disabled = busy;
  if (busy) elements.consoleStatus.textContent = label;
}

function markStage(stage) {
  state.stages.add(stage);
  const order = ["diagnostic", "explanation", "practice", "repair"];
  document.querySelectorAll("#funnel li").forEach((item, index) => {
    const itemStage = item.dataset.stage;
    item.classList.toggle("done", state.stages.has(itemStage));
    const firstIncomplete = order.findIndex((candidate) => !state.stages.has(candidate));
    item.classList.toggle("active", index === (firstIncomplete === -1 ? order.length - 1 : firstIncomplete));
  });
}

function resetStages() {
  state.stages.clear();
  state.practiceCompleted = false;
  document.querySelectorAll("#funnel li").forEach((item, index) => {
    item.classList.toggle("active", index === 0);
    item.classList.remove("done");
  });
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.add("show");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => elements.toast.classList.remove("show"), 2200);
}

function renderDiagnostic(diagnostic) {
  state.diagnostic = diagnostic;
  state.lesson = diagnostic;
  renderEditor();
  elements.problemCount.textContent = "1";
  elements.inlineDiagnostic.classList.remove("hidden");
  elements.inlineDiagnostic.querySelector(".diagnostic-code").textContent = diagnostic.code;
  elements.inlineMessage.textContent = diagnostic.message;
  const location = diagnostic.spans.find((span) => span.primary)?.lineStart ?? 1;
  elements.consoleContent.innerHTML = `
    <div class="problem-row" id="problemRow">
      <span class="problem-symbol">●</span>
      <div><strong>${escapeHtml(diagnostic.code)} · ${escapeHtml(diagnostic.message)}</strong><p>Нажмите, чтобы открыть причинный разбор.</p></div>
      <span class="problem-location">main.rs:${location}</span>
    </div>`;
  document.querySelector("#problemRow").addEventListener("click", showExplanation);
  elements.consoleStatus.textContent = "rustc отклонил программу";
  elements.learningEmpty.classList.add("hidden");
  elements.learningCard.classList.remove("hidden");

  const learning = diagnostic.learning;
  elements.learningEyebrow.textContent = learning.eyebrow;
  elements.learningTitle.textContent = learning.title;
  elements.learningCode.textContent = diagnostic.code;
  elements.learningSummary.textContent = learning.summary;
  elements.learningRule.textContent = learning.rule;
  elements.repairTitle.textContent = learning.repairTitle;
  elements.repairBox.classList.toggle("hidden", !learning.repairCode);
  elements.practiceButton.classList.toggle("hidden", !learning.practice);
  elements.causalTimeline.innerHTML = learning.causalSteps
    .map(
      (step) => `<li class="${step.tone}"><div><b><span class="line-tag">строка ${step.line ?? "—"}</span> · ${escapeHtml(step.title)}</b><code>${escapeHtml(step.detail)}</code></div></li>`,
    )
    .join("");
  markStage("diagnostic");
}

function renderSuccess(result, wasRun) {
  state.diagnostic = null;
  renderEditor();
  elements.problemCount.textContent = "0";
  elements.inlineDiagnostic.classList.add("hidden");
  elements.consoleStatus.textContent = wasRun ? "Выполнение завершено" : "Ошибок не найдено";
  const output = (result.stdout || "").trimEnd();
  elements.consoleContent.innerHTML = `
    <div class="success-line">✓ ${wasRun ? "Скомпилировано и выполнено настоящим rustc" : "Проверка rustc пройдена"}</div>
    ${output ? `<pre class="output-text">\n${escapeHtml(output)}</pre>` : ""}`;
  if (state.stages.has("diagnostic")) {
    markStage("repair");
    elements.learningEmpty.classList.add("hidden");
    elements.learningCard.classList.remove("hidden");
    elements.learningEyebrow.textContent = "ПЕТЛЯ ЗАМКНУТА";
    elements.learningTitle.textContent = "Код снова работает";
    elements.learningCode.textContent = "PASS";
    elements.learningSummary.textContent = state.practiceCompleted
      ? "Вы разобрали причину, подтвердили правило на отдельной задаче и исправили исходный проект. Это и есть проверяемая гипотеза Crabrix."
      : "Исправление подтверждено компилятором. Для полного сценария попробуйте также микро‑практику.";
    elements.learningRule.textContent = "Правильность подтверждает rustc, а не догадка интерфейса или AI.";
    elements.causalTimeline.innerHTML = `
      <li class="cool"><div><b>Диагностика получена</b><code>rustc → E0502</code></div></li>
      <li class="cool"><div><b>Причина объяснена</b><code>пересечение двух интервалов займа</code></div></li>
      <li class="hot"><div><b>Ремонт проверен</b><code>exit code 0</code></div></li>`;
    elements.repairBox.classList.add("hidden");
    elements.practiceButton.classList.toggle("hidden", state.practiceCompleted);
  }
}

function renderFailure(result) {
  elements.consoleStatus.textContent = "Проверка завершилась ошибкой";
  elements.consoleContent.innerHTML = `<div class="failure-line">× ${escapeHtml(result.message || "Не удалось выполнить код")}</div>`;
  if (result.kind === "runtime-timeout") {
    showToast("Бесконечный цикл безопасно остановлен по таймауту");
  }
}

async function compile(code, run = false) {
  const response = await fetch("/api/compile", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, run }),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function compileProject(run = false) {
  if (state.busy) return;
  setBusy(true, run ? "Сборка и запуск…" : "rustc проверяет код…");
  try {
    const result = await compile(state.code, run);
    if (result.diagnostics?.length) renderDiagnostic(result.diagnostics[0]);
    else if (result.ok) renderSuccess(result, run);
    else renderFailure(result);
  } catch {
    renderFailure({ message: "Локальный сервер недоступен. Запустите npm start." });
  } finally {
    setBusy(false);
  }
}

function showExplanation() {
  if (!state.diagnostic) return;
  markStage("explanation");
  document.querySelector("#learningPane").scrollIntoView({ behavior: "smooth", block: "start" });
}

function openPractice() {
  const practice = state.lesson?.learning.practice;
  if (!practice) return;
  markStage("explanation");
  elements.practiceTitle.textContent = practice.title;
  elements.practicePrompt.textContent = practice.prompt;
  elements.practiceCode.value = practice.starter;
  elements.practiceFeedback.className = "practice-feedback";
  elements.practiceFeedback.textContent = "Измени порядок двух строк и проверь решение настоящим компилятором.";
  elements.practiceDialog.showModal();
}

async function checkPractice() {
  if (state.busy) return;
  setBusy(true, "Проверяем упражнение…");
  elements.checkPracticeButton.textContent = "Компиляция…";
  try {
    const result = await compile(elements.practiceCode.value, true);
    const expected = state.lesson?.learning.practice?.expectedOutput;
    if (result.ok && (!expected || result.stdout.includes(expected))) {
      state.practiceCompleted = true;
      markStage("practice");
      elements.practiceFeedback.className = "practice-feedback success";
      elements.practiceFeedback.textContent = `✓ rustc принял решение${result.stdout.trim() ? ` · вывод: ${result.stdout.trim()}` : ""}`;
      elements.checkPracticeButton.textContent = "Готово";
      setTimeout(() => elements.practiceDialog.close(), 850);
      showToast("Навык закреплён. Теперь вернитесь к исходному коду.");
    } else {
      const issue = result.diagnostics?.[0];
      elements.practiceFeedback.className = "practice-feedback failure";
      elements.practiceFeedback.textContent = issue
        ? `Пока не принято: ${issue.code} · ${issue.message}`
        : `Код запустился, но ожидаемый вывод «${expected}» не получен.`;
      elements.checkPracticeButton.textContent = "Проверить снова";
    }
  } catch {
    elements.practiceFeedback.className = "practice-feedback failure";
    elements.practiceFeedback.textContent = "Не удалось связаться с локальным компилятором.";
  } finally {
    setBusy(false);
    elements.consoleStatus.textContent = state.diagnostic
      ? "rustc отклонил программу"
      : "Готово к проверке";
    if (!state.practiceCompleted) elements.checkPracticeButton.textContent = "Проверить решение";
  }
}

function applyRepair() {
  const repairCode = state.diagnostic?.learning.repairCode;
  if (!repairCode) return;
  state.code = repairCode;
  elements.codeInput.value = repairCode;
  state.diagnostic = null;
  elements.inlineDiagnostic.classList.add("hidden");
  renderEditor();
  showToast("Минимальный ремонт применён. Теперь подтвердите его rustc.");
  document.querySelector("#codeEditor").scrollIntoView({ behavior: "smooth", block: "center" });
}

function resetProject() {
  state.code = originalCode;
  state.diagnostic = null;
  state.lesson = null;
  elements.codeInput.value = originalCode;
  elements.inlineDiagnostic.classList.add("hidden");
  elements.learningCard.classList.add("hidden");
  elements.learningEmpty.classList.remove("hidden");
  elements.problemCount.textContent = "0";
  elements.consoleStatus.textContent = "Готово к проверке";
  elements.consoleContent.innerHTML = `<div class="empty-state"><span>⌘↵</span>Нажмите «Проверить», чтобы спросить настоящий rustc.</div>`;
  resetStages();
  renderEditor();
}

async function loadHealth() {
  try {
    const response = await fetch("/api/health");
    const health = await response.json();
    elements.compilerVersion.textContent = health.rustc.replace(/ \(.+$/, "") + " · LOCAL";
    elements.compilerPill.classList.toggle("ready", health.ok);
  } catch {
    elements.compilerVersion.textContent = "rustc недоступен";
  }
}

elements.codeInput.value = originalCode;
elements.codeInput.addEventListener("input", () => {
  state.code = elements.codeInput.value;
  state.diagnostic = null;
  elements.inlineDiagnostic.classList.add("hidden");
  renderEditor();
});
elements.codeInput.addEventListener("scroll", syncEditorScroll);
elements.codeInput.addEventListener("keydown", (event) => {
  if (event.key === "Tab") {
    event.preventDefault();
    const start = event.currentTarget.selectionStart;
    const end = event.currentTarget.selectionEnd;
    state.code = state.code.slice(0, start) + "    " + state.code.slice(end);
    event.currentTarget.value = state.code;
    event.currentTarget.selectionStart = event.currentTarget.selectionEnd = start + 4;
    renderEditor();
  }
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    compileProject(false);
  }
});
elements.checkButton.addEventListener("click", () => compileProject(false));
elements.runButton.addEventListener("click", () => compileProject(true));
elements.resetButton.addEventListener("click", resetProject);
elements.openExplanation.addEventListener("click", showExplanation);
elements.repairButton.addEventListener("click", applyRepair);
elements.practiceButton.addEventListener("click", openPractice);
elements.checkPracticeButton.addEventListener("click", checkPractice);

renderEditor();
loadHealth();
