// Havooch prototype: the copy buttons, the home page's table of contents,
// the studio callouts, and the CLI terminal and packet. One script for all
// three pages; each part does nothing when its markup is absent. The pixel
// world is in world.js. Every page reads fully without either script.
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

  // The table of contents -----------------------------------------------------
  // Its links scroll to the home page's sections (the smooth scroll is CSS, so
  // reduced motion turns it off) and the section in view is marked with
  // aria-current. On phones the list is a sheet behind the toggle button.
  const toc = document.querySelector(".toc");
  if (toc) {
    const toggle = toc.querySelector(".toc-toggle");
    const links = Array.from(toc.querySelectorAll('a[href^="#"]'));
    const targets = links.map((a) => document.getElementById(a.hash.slice(1)));
    const setOpen = (open) => {
      toc.classList.toggle("open", open);
      if (toggle) toggle.setAttribute("aria-expanded", String(open));
    };
    if (toggle) toggle.addEventListener("click", () => setOpen(!toc.classList.contains("open")));
    links.forEach((a) => a.addEventListener("click", () => setOpen(false)));
    document.addEventListener("keydown", (e) => { if (e.key === "Escape") setOpen(false); });
    document.addEventListener("click", (e) => { if (!toc.contains(e.target)) setOpen(false); });

    let queued = false;
    const spy = () => {
      queued = false;
      const line = innerHeight * 0.35;
      let current = 0;
      targets.forEach((t, i) => { if (t && t.getBoundingClientRect().top <= line) current = i; });
      if (innerHeight + scrollY >= document.documentElement.scrollHeight - 4) current = links.length - 1;
      links.forEach((a, i) => (i === current ? a.setAttribute("aria-current", "location") : a.removeAttribute("aria-current")));
    };
    addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(spy); } }, { passive: true });
    addEventListener("resize", spy);
    spy();
  }

  // The studio callouts -------------------------------------------------------
  // Shown once when the screenshot scrolls into view, then hover and focus take
  // over. With reduced motion they only show on hover.
  const callouts = document.querySelector(".callouts");
  if (callouts && !reduced.matches) {
    callouts.querySelectorAll(".pin").forEach((pin) => { pin.tabIndex = 0; });
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver((entries) => {
        if (!entries[0].isIntersecting) return;
        io.disconnect();
        callouts.classList.add("show");
        setTimeout(() => callouts.classList.remove("show"), 3200);
      }, { threshold: 0.6 });
      io.observe(callouts);
    }
  }

  // The terminal --------------------------------------------------------------
  // Lines appear one at a time, like a session scrolling by. With reduced
  // motion, or without JS, every line is simply there.
  const term = document.getElementById("term");
  const replay = document.querySelector(".term-replay");
  if (term && replay) {
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

  // The packet ----------------------------------------------------------------
  const lanes = document.querySelector("[data-wire]");
  if (lanes && !reduced.matches && "IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      lanes.classList.toggle("live", entries[0].isIntersecting);
    }, { threshold: 0.2 }).observe(lanes);
  }
})();
