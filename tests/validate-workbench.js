const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "workbench.html"), "utf8");
const match = html.match(/<script>([\s\S]*?)<\/script>/);
if (!match) throw new Error("workbench.html does not contain an inline script.");

const jsonInput = { value: "", addEventListener() {} };
const context = {
  console,
  clearTimeout,
  setTimeout,
  navigator: {},
  window: { isSecureContext: false },
  document: {
    getElementById(id) {
      if (id === "jsonInput") return jsonInput;
      return {
        classList: { add() {}, remove() {} },
        textContent: "",
        innerHTML: "",
        scrollIntoView() {},
        querySelectorAll() { return []; },
      };
    },
    querySelector() {
      return { textContent: "", classList: { add() {}, remove() {} } };
    },
    createElement() {
      return {
        style: {},
        select() {},
        remove() {},
        value: "",
      };
    },
    body: { appendChild() {} },
    execCommand() { return true; },
  },
};

vm.createContext(context);
vm.runInContext(match[1], context, { filename: "workbench-inline.js" });

const sample = {
  decisions: [{
    id: "col_001",
    title: "栏目归属",
    detail: "选择最合适的栏目",
    type: "single",
    options: [
      { id: "a", label: "行业监管动态" },
      { id: "b", label: "政策法规发布" },
    ],
  }],
};
const raw = JSON.stringify(sample);
const markdown = `说明文字\n\`\`\`json\n${raw}\n\`\`\``;
const mixed = `请处理以下决策：${raw}谢谢`;

for (const input of [raw, markdown, mixed]) {
  const extracted = context.extractJSON(input);
  if (!extracted) throw new Error("Failed to extract a supported JSON form.");
  const parsed = JSON.parse(extracted);
  if (!Array.isArray(parsed.decisions) || parsed.decisions.length !== 1) {
    throw new Error("Decision protocol was not preserved.");
  }
}

for (const functionName of ["doRender", "selectOption", "buildResult", "copyResultAsPrompt"]) {
  if (typeof context[functionName] !== "function") {
    throw new Error(`Workbench function is missing: ${functionName}`);
  }
}

console.log("Workbench contract checks passed.");
