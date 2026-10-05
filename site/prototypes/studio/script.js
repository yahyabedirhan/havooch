// Havooch "studio" prototype: copy buttons and the hero callouts.
// The page reads fully without this script.
(() => {
  "use strict";

  const copyText = async (text) => {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.cssText = "position:fixed;opacity:0";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    if (!ok) throw new Error("copy refused");
  };

  const status = document.createElement("p");
  status.className = "skip";
  status.setAttribute("role", "status");
  document.body.appendChild(status);

  document.querySelectorAll("button[data-copy]").forEach((button) => {
    let timer;
    button.addEventListener("click", async () => {
      const source = document.getElementById(button.dataset.copy);
      if (!source) return;
      clearTimeout(timer);
      try {
        await copyText(source.textContent.trim());
        button.classList.add("done");
        button.textContent = "Copied";
        status.textContent = "Command copied.";
      } catch {
        button.textContent = "Select";
        const range = document.createRange();
        range.selectNodeContents(source);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        status.textContent = "Copy failed. The command is selected; copy it.";
      }
      timer = setTimeout(() => {
        button.classList.remove("done");
        button.textContent = "Copy";
      }, 1600);
    });
  });

  // Show the callouts once, when the screenshot scrolls into view, then let
  // hover and focus take over. With reduced motion they only show on hover.
  const callouts = document.querySelector(".callouts");
  if (!callouts || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  callouts.querySelectorAll(".pin").forEach((pin) => { pin.tabIndex = 0; });
  if (!("IntersectionObserver" in window)) return;
  const io = new IntersectionObserver((entries) => {
    if (!entries[0].isIntersecting) return;
    io.disconnect();
    callouts.classList.add("show");
    setTimeout(() => callouts.classList.remove("show"), 3200);
  }, { threshold: 0.6 });
  io.observe(callouts);
})();
