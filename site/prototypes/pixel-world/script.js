// Havooch "pixel-world" prototype: the copy buttons. The world itself is in
// world.js. The page reads fully without either script.
(() => {
  "use strict";
  const copyText = async (text) => {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    const area = document.createElement("textarea");
    area.value = text; area.setAttribute("readonly", ""); area.style.cssText = "position:fixed;opacity:0";
    document.body.appendChild(area); area.select();
    const ok = document.execCommand("copy"); area.remove();
    if (!ok) throw new Error("copy refused");
  };
  const status = document.createElement("p");
  status.className = "skip"; status.setAttribute("role", "status");
  document.body.appendChild(status);
  document.querySelectorAll("button[data-copy]").forEach((button) => {
    let timer;
    button.addEventListener("click", async () => {
      const source = document.getElementById(button.dataset.copy);
      if (!source) return;
      clearTimeout(timer);
      try {
        await copyText(source.textContent.trim());
        button.classList.add("done"); button.textContent = "Copied"; status.textContent = "Command copied.";
      } catch {
        button.textContent = "Select";
        const range = document.createRange(); range.selectNodeContents(source);
        const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range);
        status.textContent = "Copy failed. The command is selected; copy it.";
      }
      timer = setTimeout(() => { button.classList.remove("done"); button.textContent = "Copy"; }, 1600);
    });
  });
})();
