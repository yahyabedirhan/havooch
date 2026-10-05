// Havooch "wire" prototype: copy buttons, the terminal that plays one send,
// and the packet on the wire. The page reads fully without this script.
(() => {
  "use strict";
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");

  // Copy buttons ------------------------------------------------------------
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

  // The terminal ------------------------------------------------------------
  // Lines appear one at a time, like a session scrolling by. With reduced
  // motion, or without JS, every line is simply there.
  const term = document.getElementById("term");
  const replay = document.querySelector(".term-replay");
  if (term) {
    const lines = Array.from(term.querySelectorAll(".l"));
    const showAll = () => { lines.forEach((l) => l.classList.add("on")); term.removeAttribute("data-play"); };
    let timers = [];
    const play = () => {
      timers.forEach(clearTimeout); timers = [];
      term.setAttribute("data-play", "");
      lines.forEach((l) => l.classList.remove("on"));
      let t = 300;
      lines.forEach((l, i) => {
        timers.push(setTimeout(() => l.classList.add("on"), t));
        t += l.classList.contains("out") ? 900 : l.classList.contains("ans") ? 1100 : 520 + (i % 3) * 120;
      });
      timers.push(setTimeout(() => { replay.hidden = false; }, t + 400));
    };
    if (reduced.matches) {
      showAll();
    } else if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver((entries) => {
        if (!entries[0].isIntersecting) return;
        io.disconnect(); play();
      }, { threshold: 0.4 });
      io.observe(term);
    } else {
      play();
    }
    replay.addEventListener("click", () => { replay.hidden = true; play(); });
  }

  // The packet --------------------------------------------------------------
  const lanes = document.querySelector("[data-wire]");
  if (lanes && !reduced.matches && "IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      lanes.classList.toggle("live", entries[0].isIntersecting);
    }, { threshold: 0.2 }).observe(lanes);
  }
})();
