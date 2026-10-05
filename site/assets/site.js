// Havooch landing page: the copy buttons and the review-loop illustration.
// No dependencies. The page reads fully without this script.

(() => {
  "use strict";

  // Copy buttons -----------------------------------------------------------
  // Each button names the <code> it copies with data-copy="<id>".

  const copyText = async (text) => {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    // Fallback for http:// previews and older browsers.
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    if (!ok) throw new Error("copy refused");
  };

  const status = document.createElement("p");
  status.className = "visually-hidden";
  status.setAttribute("role", "status");
  document.body.appendChild(status);

  document.querySelectorAll("button[data-copy]").forEach((button) => {
    const label = button.querySelector(".copy-label");
    let timer;
    button.addEventListener("click", async () => {
      const source = document.getElementById(button.dataset.copy);
      if (!source) return;
      clearTimeout(timer);
      try {
        await copyText(source.textContent.trim());
        button.classList.remove("is-failed");
        button.classList.add("is-copied");
        label.textContent = "Copied";
        status.textContent = "Command copied to the clipboard.";
      } catch {
        button.classList.add("is-failed");
        label.textContent = "Select";
        status.textContent = "Copy failed. Select the command and copy it.";
        const range = document.createRange();
        range.selectNodeContents(source);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
      timer = setTimeout(() => {
        button.classList.remove("is-copied", "is-failed");
        label.textContent = "Copy";
      }, 1800);
    });
  });

  // The review loop --------------------------------------------------------
  // Four steps on one illustrated window. It plays while it is on screen,
  // stops when the person picks a step, and never plays with reduced motion.

  const loop = document.querySelector(".loop");
  if (!loop) return;

  const tabs = Array.from(loop.querySelectorAll("[role=tab]"));
  const panel = loop.querySelector("[role=tabpanel]");
  const caption = loop.querySelector("#loop-caption");
  const toggle = loop.querySelector(".loop-toggle");
  const STEP_MS = 3600;
  loop.style.setProperty("--step-ms", STEP_MS + "ms");

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  let step = 1;
  let timer = null;
  let visible = false;
  let stoppedByPerson = false;

  const show = (n, { focus = false } = {}) => {
    step = n;
    loop.dataset.step = String(n);
    tabs.forEach((tab, i) => {
      const on = i + 1 === n;
      tab.setAttribute("aria-selected", String(on));
      tab.tabIndex = on ? 0 : -1;
      if (on && focus) tab.focus();
    });
    panel.setAttribute("aria-labelledby", tabs[n - 1].id);
    caption.textContent = tabs[n - 1].textContent.replace(/\s+/g, " ").trim();
  };

  const playing = () => timer !== null;
  const stop = () => {
    clearInterval(timer);
    timer = null;
    loop.classList.remove("is-playing");
    toggle.textContent = "Play";
    toggle.setAttribute("aria-pressed", "true");
  };
  const play = () => {
    if (playing() || reduced.matches) return;
    loop.classList.remove("is-playing");
    void loop.offsetWidth; // restart the progress bar
    loop.classList.add("is-playing");
    timer = setInterval(() => {
      show(step % tabs.length + 1);
      loop.classList.remove("is-playing");
      void loop.offsetWidth;
      loop.classList.add("is-playing");
    }, STEP_MS);
    toggle.textContent = "Pause";
    toggle.setAttribute("aria-pressed", "false");
  };
  const update = () => {
    toggle.hidden = reduced.matches;
    if (visible && !stoppedByPerson && !reduced.matches) play();
    else stop();
  };

  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => {
      stoppedByPerson = true;
      stop();
      show(i + 1);
    });
    tab.addEventListener("keydown", (e) => {
      const keys = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 };
      let next = null;
      if (e.key in keys) next = (i + keys[e.key] + tabs.length) % tabs.length + 1;
      if (e.key === "Home") next = 1;
      if (e.key === "End") next = tabs.length;
      if (next === null) return;
      e.preventDefault();
      stoppedByPerson = true;
      stop();
      show(next, { focus: true });
    });
  });

  toggle.addEventListener("click", () => {
    if (playing()) {
      stoppedByPerson = true;
      stop();
    } else {
      stoppedByPerson = false;
      play();
    }
  });

  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      update();
    }, { threshold: 0.35 }).observe(panel);
  } else {
    visible = true;
  }
  reduced.addEventListener?.("change", update);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stop();
    else update();
  });

  show(1);
  update();
})();
