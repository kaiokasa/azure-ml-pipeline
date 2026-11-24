/* Dashboard: polls GET {apiBase}/api/recent every 30 s and renders a table + 2 Chart.js charts. */
(() => {
  const REFRESH_MS = 30_000;
  const base = (window.PIPELINE_CONFIG && window.PIPELINE_CONFIG.apiBase) || "http://localhost:7071";
  const url = `${base.replace(/\/$/, "")}/api/recent`;
  const $ = (id) => document.getElementById(id);
  let negChart, latChart;

  const fmtPct = (x) => `${(x * 100).toFixed(1)} %`;
  const fmtTime = (iso) => new Date(iso).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "medium" });
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  function initCharts() {
    Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
    Chart.defaults.color = "#66716b";
    negChart = new Chart($("chart-neg"), {
      type: "bar",
      data: { labels: [], datasets: [{ label: "% négatifs", data: [], backgroundColor: "#c2410c", borderRadius: 3 }] },
      options: {
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: { y: { min: 0, max: 100, ticks: { callback: (v) => `${v} %` } }, x: { ticks: { maxRotation: 45 } } },
      },
    });
    latChart = new Chart($("chart-lat"), {
      type: "line",
      data: {
        labels: [],
        datasets: [
          { label: "Latence modèle", data: [], borderColor: "#0f766e", backgroundColor: "#0f766e", tension: 0.25 },
          { label: "Bout en bout", data: [], borderColor: "#94a3b8", backgroundColor: "#94a3b8", tension: 0.25 },
        ],
      },
      options: { maintainAspectRatio: false, scales: { y: { beginAtZero: true } } },
    });
  }

  function render(items) {
    const rows = $("rows");
    if (!items.length) {
      rows.innerHTML = '<tr><td colspan="8" class="empty">Aucune donnée pour l’instant.</td></tr>';
    } else {
      rows.innerHTML = items
        .map(
          (r) => `<tr>
            <td>${esc(fmtTime(r.timestamp))}</td>
            <td>${esc(r.fileName)}</td>
            <td><span class="tag ${esc(r.prediction)}">${r.prediction === "negative" ? "négatif" : "positif"}</span></td>
            <td class="num">${fmtPct(r.confidence)}</td>
            <td class="num">${r.count}</td>
            <td class="num">${fmtPct(r.negativeShare)}</td>
            <td>${esc(r.modelVersion)}</td>
            <td class="num">${Math.round(r.durationMs)}</td>
          </tr>`,
        )
        .join("");
    }

    const lines = items.reduce((s, r) => s + r.count, 0);
    const negLines = items.reduce((s, r) => s + r.negativeShare * r.count, 0);
    const meanDur = items.length ? items.reduce((s, r) => s + r.durationMs, 0) / items.length : 0;
    $("k-files").textContent = items.length;
    $("k-lines").textContent = lines;
    $("k-neg").textContent = lines ? fmtPct(negLines / lines) : "–";
    $("k-dur").textContent = items.length ? `${Math.round(meanDur)} ms` : "–";

    const chrono = [...items].reverse();
    const labels = chrono.map((r) => r.fileName.length > 18 ? `${r.fileName.slice(0, 16)}…` : r.fileName);
    negChart.data.labels = labels;
    negChart.data.datasets[0].data = chrono.map((r) => +(r.negativeShare * 100).toFixed(1));
    negChart.update();
    latChart.data.labels = labels;
    latChart.data.datasets[0].data = chrono.map((r) => r.modelLatencyMs ?? null);
    latChart.data.datasets[1].data = chrono.map((r) => r.durationMs);
    latChart.update();
  }

  async function refresh() {
    try {
      const res = await fetch(url, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      render(await res.json());
      $("dot").className = "dot ok";
      $("updated").textContent = `Mis à jour à ${new Date().toLocaleTimeString("fr-FR")}`;
    } catch (err) {
      $("dot").className = "dot err";
      $("updated").textContent = `Erreur : ${err.message}`;
    }
  }

  window.addEventListener("DOMContentLoaded", () => {
    $("src").textContent = url;
    initCharts();
    refresh();
    setInterval(refresh, REFRESH_MS);
  });
})();
