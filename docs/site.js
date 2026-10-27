// Spider Solitaire website: small progressive enhancements, no libraries. The page works without it.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.remove("no-js");
  root.classList.add("js");
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  var still = /[?&]still\b/.test(window.location.search);
  if (still) { root.classList.add("still"); }

  // Screenshots: drop the skeleton once each picture has loaded.
  document.querySelectorAll(".shot img").forEach(function (img) {
    var done = function () { img.closest(".shot").classList.add("loaded"); };
    if (img.complete && img.naturalWidth > 0) { done(); } else {
      img.addEventListener("load", done, { once: true });
      img.addEventListener("error", done, { once: true });
    }
  });

  // Scroll reveals: each section rises once (IntersectionObserver, never a scroll listener).
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -10% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  // Tagline: words light up one at a time as they cross a line 60% down the viewport.
  var tagline = document.querySelector("[data-tagline]");
  if (tagline) {
    var words = [];
    tagline.querySelectorAll("[data-line]").forEach(function (line) {
      var parts = line.textContent.trim().split(/\s+/);
      line.textContent = "";
      parts.forEach(function (w, i) {
        var span = document.createElement("span");
        span.className = "word";
        span.textContent = w;
        line.appendChild(span);
        if (i < parts.length - 1) { line.appendChild(document.createTextNode(" ")); }
        words.push(span);
      });
    });
    var ticking = false;
    var update = function () {
      ticking = false;
      var trigger = window.innerHeight * 0.6;
      words.forEach(function (w) {
        w.classList.toggle("on", w.getBoundingClientRect().top < trigger);
      });
    };
    var request = function () { if (!ticking) { ticking = true; window.requestAnimationFrame(update); } };
    if (reduceMotion.matches || still) {
      words.forEach(function (w) { w.classList.add("on"); });
    } else {
      window.addEventListener("scroll", request, { passive: true }); // throttled through rAF
      window.addEventListener("resize", request);
      update();
    }
  }

  // Mobile menu: full height panel, links arrive in order (60 ms apart, 400 ms at most).
  var toggle = document.querySelector(".menu-toggle");
  var menu = document.getElementById("mobile-menu");
  if (toggle && menu) {
    var links = menu.querySelectorAll("a");
    var step = Math.min(60, 400 / Math.max(1, links.length));
    var setOpen = function (open) {
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
      menu.classList.toggle("open", open);
      menu.hidden = false;
      menu.setAttribute("aria-hidden", String(!open));
      document.body.style.overflow = open ? "hidden" : "";
      links.forEach(function (a, i) {
        a.style.transitionDelay = open ? (i * step) + "ms" : "0ms";
        a.tabIndex = open ? 0 : -1;
      });
      if (open && links[0]) { links[0].focus({ preventScroll: true }); }
    };
    toggle.addEventListener("click", function () { setOpen(toggle.getAttribute("aria-expanded") !== "true"); });
    links.forEach(function (a) { a.addEventListener("click", function () { setOpen(false); }); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") { setOpen(false); toggle.focus(); }
    });
    links.forEach(function (a) { a.tabIndex = -1; });
  }

  // Navigation: mark the section in view as current.
  var navLinks = document.querySelectorAll(".nav-links a[href^='#']");
  if (navLinks.length && "IntersectionObserver" in window) {
    var byId = {};
    navLinks.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) { return; }
        navLinks.forEach(function (a) { a.removeAttribute("aria-current"); });
        var link = byId[e.target.id];
        if (link) { link.setAttribute("aria-current", "true"); }
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    Object.keys(byId).forEach(function (id) {
      var section = document.getElementById(id);
      if (section) { spy.observe(section); }
    });
  }

  // Copy buttons for the Terminal command, with an inline result message.
  document.querySelectorAll("[data-copy]").forEach(function (button) {
    var status = document.getElementById(button.getAttribute("aria-describedby"));
    button.addEventListener("click", function () {
      var text = document.getElementById(button.getAttribute("data-copy")).textContent;
      var report = function (message) { if (status) { status.textContent = message; } };
      if (!navigator.clipboard) { report("Copying is not available here. Select the command and copy it."); return; }
      navigator.clipboard.writeText(text).then(function () {
        report("Command copied. Paste it into Terminal.");
      }, function () {
        report("Copying failed. Select the command and copy it.");
      });
    });
  });
})();
